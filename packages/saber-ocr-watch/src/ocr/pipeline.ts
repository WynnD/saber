import { execFile as execFileCb } from "child_process";
import { mkdtemp, mkdir, readdir, rm, writeFile } from "fs/promises";
import { join } from "path";
import { promisify } from "util";
import { tmpdir } from "os";
import { config } from "../config.js";
import { readSbn, resolveAssetPath, type EmbeddedAsset } from "../notes/sbn-reader.js";
import { extractQuillText } from "./quill.js";
import { ocrImage } from "./ollama.js";

const execFile = promisify(execFileCb);

async function createTempDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "saber-ocr-"));
}

export interface OcrResult {
  notePath: string;
  ocrPath: string;
  pageCount: number;
  quillText: string;
  ocrText: string;
  pdfExtracted: boolean;
  elapsed: number;
}

/** "auto" = extract from embedded PDF if note has one (no strokes/quill), "force" = always try, "never" = skip */
export type PdfExtractMode = "auto" | "force" | "never";

export interface OcrOptions {
  pdfExtract?: PdfExtractMode;
}

/** Find embedded PDF assets in the note */
function findEmbeddedPdfs(doc: { pages: Array<{ backgroundAsset: EmbeddedAsset | null }> }): EmbeddedAsset[] {
  const seen = new Set<number>();
  const pdfs: EmbeddedAsset[] = [];
  for (const page of doc.pages) {
    if (page.backgroundAsset?.extension === ".pdf" && !seen.has(page.backgroundAsset.index)) {
      seen.add(page.backgroundAsset.index);
      pdfs.push(page.backgroundAsset);
    }
  }
  return pdfs;
}

/** Check if a note is PDF-only: has PDF background but no strokes and no quill text */
function isPdfOnly(doc: { pages: Array<{ quillDelta: unknown[] | null; hasStrokes: boolean; backgroundAsset: EmbeddedAsset | null }> }): boolean {
  return doc.pages.every((p) => !p.hasStrokes && !p.quillDelta) &&
    doc.pages.some((p) => p.backgroundAsset?.extension === ".pdf");
}

/** Try extracting text from a PDF file via pdftotext */
async function extractPdfText(pdfPath: string): Promise<string> {
  const { stdout } = await execFile("pdftotext", ["-layout", pdfPath, "-"]);
  return stdout.trim();
}

/** Rasterize a PDF and OCR each page via vision */
async function ocrPdfPages(pdfPath: string, imgDir: string): Promise<{ text: string; pageCount: number }> {
  await mkdir(imgDir, { recursive: true });
  await execFile("pdftoppm", ["-png", "-r", "200", pdfPath, join(imgDir, "page")]);
  const files = (await readdir(imgDir)).filter((f) => f.endsWith(".png")).sort();
  const rawTexts = await Promise.all(files.map((f) => ocrImage(join(imgDir, f))));
  const pageTexts = rawTexts.map((text, i) => `--- Page ${i + 1} ---\n${text}`);
  return { text: pageTexts.join("\n\n"), pageCount: files.length };
}

export async function ocrNote(notePath: string, opts: OcrOptions = {}): Promise<OcrResult> {
  const pdfExtract = opts.pdfExtract ?? "auto";
  const start = Date.now();
  const ocrPath = notePath + ".ocr";
  const tempDir = await createTempDir();
  const imgDir = join(tempDir, "pages");

  try {
    // 1. Parse the .sbn2 BSON
    const doc = await readSbn(notePath);

    // 2. Extract quill text (free — no OCR needed for typed content)
    const quillParts: string[] = [];
    for (const page of doc.pages) {
      if (page.quillDelta) {
        const text = extractQuillText(page.quillDelta);
        if (text) quillParts.push(text);
      }
    }
    const quillText = quillParts.join("\n\n");

    // 3. Check for embedded PDFs and try pdftotext on the ORIGINAL PDF
    const embeddedPdfs = findEmbeddedPdfs(doc);
    const shouldExtractPdf = pdfExtract === "force" ||
      (pdfExtract === "auto" && isPdfOnly(doc));

    let pdfText = "";
    let pdfExtracted = false;
    let embeddedPdfPath: string | null = null;

    if (shouldExtractPdf && embeddedPdfs.length > 0) {
      // Resolve the embedded PDF to a file path
      const asset = embeddedPdfs[0];
      const resolved = await resolveAssetPath(notePath, asset, doc.inlineAssets);

      if ("path" in resolved) {
        embeddedPdfPath = resolved.path;
      } else {
        // Write inline asset to temp file
        embeddedPdfPath = join(tempDir, "embedded.pdf");
        await writeFile(embeddedPdfPath, resolved.data);
      }

      pdfText = await extractPdfText(embeddedPdfPath);
      if (pdfText) {
        pdfExtracted = true;
        console.error(`[saber-ocr-watch] pdftotext extracted ${pdfText.length} chars from embedded PDF, skipping vision OCR`);
      }
    }

    let ocrText = "";
    let pageCount = 0;

    if (!pdfExtracted) {
      // 4. Determine what to OCR: embedded PDF directly, or render via sbn2pdf
      let pdfToOcr: string;

      if (embeddedPdfPath && isPdfOnly(doc)) {
        // Use the original embedded PDF — better quality than re-rendering
        pdfToOcr = embeddedPdfPath;
        console.error(`[saber-ocr-watch] Using embedded PDF directly for OCR`);
      } else {
        // Render via sbn2pdf (has strokes, quill, or mixed content)
        pdfToOcr = join(tempDir, "rendered.pdf");
        const [cmd, ...cmdArgs] = config.sbn2pdfCmd.split(/\s+/);
        await execFile(cmd, [...cmdArgs, notePath, pdfToOcr]);
      }

      // 5. Rasterize and OCR
      const result = await ocrPdfPages(pdfToOcr, imgDir);
      ocrText = result.text;
      pageCount = result.pageCount;
    }

    // 6. Combine all text sources
    const sections: string[] = [];
    if (quillText) {
      sections.push("=== Typed Text ===\n" + quillText);
    }
    if (pdfExtracted) {
      sections.push("=== PDF Text ===\n" + pdfText);
    }
    if (ocrText) {
      sections.push("=== Handwritten/Visual Content ===\n" + ocrText);
    }
    const fullText = sections.join("\n\n");

    // 7. Write .sbn2.ocr
    await writeFile(ocrPath, fullText, "utf-8");

    return {
      notePath,
      ocrPath,
      pageCount,
      quillText,
      ocrText,
      pdfExtracted,
      elapsed: Date.now() - start,
    };
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }
}
