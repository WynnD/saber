import { readFile, access } from "fs/promises";
import { BSON, Binary } from "bson";

export interface EmbeddedAsset {
  /** Asset index in the top-level 'a' array or sidecar file index */
  index: number;
  /** File extension (e.g. ".pdf", ".png") */
  extension: string;
  /** PDF page index within a multi-page PDF, if applicable */
  pdfPageIndex?: number;
}

export interface SbnPage {
  width: number;
  height: number;
  quillDelta: unknown[] | null;
  hasStrokes: boolean;
  hasImages: boolean;
  /** Background image asset info (imported PDF or image) */
  backgroundAsset: EmbeddedAsset | null;
}

export interface SbnDocument {
  version: number;
  pages: SbnPage[];
  /** Inline binary assets from the 'a' array */
  inlineAssets: Buffer[];
}

export async function readSbn(filePath: string): Promise<SbnDocument> {
  const buf = await readFile(filePath);
  const doc = BSON.deserialize(buf);

  const version = doc.v ?? 0;
  const pages: SbnPage[] = [];

  // Extract inline assets
  const inlineAssets: Buffer[] = [];
  if (Array.isArray(doc.a)) {
    for (const asset of doc.a) {
      if (asset instanceof Binary) {
        inlineAssets.push(asset.buffer as Buffer);
      } else if (Buffer.isBuffer(asset)) {
        inlineAssets.push(asset);
      }
    }
  }

  if (Array.isArray(doc.z)) {
    for (const page of doc.z) {
      let backgroundAsset: EmbeddedAsset | null = null;
      if (page.b && typeof page.b === "object") {
        backgroundAsset = {
          index: page.b.a ?? 0,
          extension: page.b.e ?? ".png",
          pdfPageIndex: page.b.pdfi,
        };
      }

      pages.push({
        width: page.w ?? 1000,
        height: page.h ?? 1400,
        quillDelta: Array.isArray(page.q) ? page.q : null,
        hasStrokes: Array.isArray(page.s) && page.s.length > 0,
        hasImages: (Array.isArray(page.i) && page.i.length > 0) || !!page.b,
        backgroundAsset,
      });
    }
  }

  return { version, pages, inlineAssets };
}

/**
 * Resolve an embedded asset to a file path.
 * Assets are either inline (in the 'a' array) or sidecar files (<sbn2path>.<index>).
 */
export async function resolveAssetPath(
  sbn2Path: string,
  asset: EmbeddedAsset,
  inlineAssets: Buffer[],
): Promise<{ path: string; isTemp: false } | { data: Buffer; isTemp: true }> {
  // Validate asset index to prevent path traversal
  if (!Number.isInteger(asset.index) || asset.index < 0) {
    throw new Error(`Invalid asset index: ${asset.index}`);
  }

  // Check sidecar file first
  const sidecarPath = `${sbn2Path}.${asset.index}`;
  try {
    await access(sidecarPath);
    return { path: sidecarPath, isTemp: false };
  } catch {
    // Fall through to inline
  }

  // Inline asset
  if (inlineAssets[asset.index]) {
    return { data: inlineAssets[asset.index], isTemp: true };
  }

  throw new Error(`Asset ${asset.index} not found (no sidecar or inline data)`);
}
