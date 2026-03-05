import { readdir, stat } from "fs/promises";
import { join, relative } from "path";
import { config } from "../config.js";

export interface NoteInfo {
  /** Absolute path to the .sbn2 file */
  path: string;
  /** Note name (relative path without extension) */
  name: string;
  /** mtime of the .sbn2 file */
  modified: Date;
  /** Whether a .sbn2.ocr sibling exists and is fresh */
  ocrCached: boolean;
  /** Path to the .ocr file */
  ocrPath: string;
}

async function exists(p: string): Promise<boolean> {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

export async function discoverNotes(
  dir?: string,
): Promise<NoteInfo[]> {
  const notesDir = dir ?? config.notesDir;
  const notes: NoteInfo[] = [];

  async function walk(d: string) {
    const entries = await readdir(d, { withFileTypes: true });
    for (const entry of entries) {
      const full = join(d, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
      } else if (entry.name.endsWith(".sbn2")) {
        const s = await stat(full);
        const ocrPath = full + ".ocr";
        let ocrCached = false;
        if (await exists(ocrPath)) {
          const ocrStat = await stat(ocrPath);
          ocrCached = ocrStat.mtimeMs >= s.mtimeMs;
        }
        notes.push({
          path: full,
          name: relative(notesDir, full).replace(/\.sbn2$/, ""),
          modified: s.mtime,
          ocrCached,
          ocrPath,
        });
      }
    }
  }

  await walk(notesDir);
  return notes;
}

/** Find a note by name (fuzzy: case-insensitive substring match) */
export async function findNote(
  query: string,
  dir?: string,
): Promise<NoteInfo | undefined> {
  const notes = await discoverNotes(dir);
  const lower = query.toLowerCase();
  // Exact match first
  const exact = notes.find((n) => n.name.toLowerCase() === lower);
  if (exact) return exact;
  // Substring match
  return notes.find((n) => n.name.toLowerCase().includes(lower));
}
