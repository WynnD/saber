import { watch } from "fs";
import { config } from "../config.js";
import { discoverNotes } from "../notes/discovery.js";
import { ocrNote } from "../ocr/pipeline.js";
import { basename } from "path";

const DEBOUNCE_MS = 2000;

export async function startWatcher(): Promise<void> {
  const dir = config.notesDir;
  console.error(`[saber-ocr-watch] Watching ${dir}`);

  // Initial scan: OCR any notes with stale/missing cache
  console.error("[saber-ocr-watch] Initial scan...");
  const notes = await discoverNotes();
  const stale = notes.filter((n) => !n.ocrCached);
  if (stale.length > 0) {
    console.error(`[saber-ocr-watch] ${stale.length} notes need OCR`);
    for (const note of stale) {
      await processNote(note.path);
    }
  }
  console.error(`[saber-ocr-watch] Initial scan complete. Watching for changes...`);

  // Watch for changes
  const timers = new Map<string, ReturnType<typeof setTimeout>>();

  watch(dir, { recursive: true }, (_event, filename) => {
    if (!filename || !filename.endsWith(".sbn2")) return;
    // Ignore .ocr files
    if (filename.endsWith(".ocr")) return;

    const fullPath = `${dir}/${filename}`;

    // Debounce: Saber may write multiple times during save
    const existing = timers.get(fullPath);
    if (existing) clearTimeout(existing);

    timers.set(
      fullPath,
      setTimeout(() => {
        timers.delete(fullPath);
        processNote(fullPath);
      }, DEBOUNCE_MS),
    );
  });
}

async function processNote(notePath: string): Promise<void> {
  const name = basename(notePath, ".sbn2");
  try {
    console.error(`[saber-ocr-watch] OCR'ing "${name}"...`);
    const result = await ocrNote(notePath);
    const secs = (result.elapsed / 1000).toFixed(1);
    console.error(
      `[saber-ocr-watch] OCR'd "${name}" (${result.pageCount} pages, ${secs}s)`,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes("ECONNREFUSED") || msg.includes("fetch failed")) {
      console.error(
        `[saber-ocr-watch] Ollama unavailable, skipping "${name}": ${msg}`,
      );
    } else {
      console.error(`[saber-ocr-watch] Failed to OCR "${name}": ${msg}`);
    }
  }
}
