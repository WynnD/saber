import { readdir, stat } from "fs/promises";
import { join, relative, basename } from "path";
import { config } from "../config.js";
import {
  initDecryption,
  decryptFileName,
  type DecryptionContext,
} from "../crypto.js";

export interface NoteInfo {
  /** Absolute path to the file (.sbn2 or .sbe) */
  path: string;
  /** Decrypted note name (relative path without extension) */
  name: string;
  /** mtime of the note file */
  modified: Date;
  /** Whether an OCR cache file exists and is fresh */
  ocrCached: boolean;
  /** Path to the .ocr file */
  ocrPath: string;
  /** Whether the note is encrypted (.sbe) */
  encrypted: boolean;
}

async function exists(p: string): Promise<boolean> {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

let _ctx: DecryptionContext | null = null;

/** Get or lazily init decryption context */
export async function getDecryptionContext(): Promise<DecryptionContext | null> {
  if (_ctx) return _ctx;
  if (!config.encPassword) return null;
  _ctx = await initDecryption();
  return _ctx;
}

export async function discoverNotes(dir?: string): Promise<NoteInfo[]> {
  const notesDir = dir ?? config.notesDir;
  const notes: NoteInfo[] = [];
  const ctx = await getDecryptionContext();

  async function walk(d: string) {
    const entries = await readdir(d, { withFileTypes: true });
    for (const entry of entries) {
      const full = join(d, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
      } else if (entry.name.endsWith(".sbn2")) {
        // Unencrypted note
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
          encrypted: false,
        });
      } else if (entry.name.endsWith(".sbe") && ctx) {
        // Encrypted note — decrypt the file name
        const encHex = basename(entry.name, ".sbe");
        try {
          const decryptedPath = decryptFileName(encHex, ctx);
          const noteName = decryptedPath.replace(/\.sbn2$/, "").replace(/^\//, "");
          const s = await stat(full);
          // OCR cache lives next to the encrypted file
          const ocrPath = full + ".ocr";
          let ocrCached = false;
          if (await exists(ocrPath)) {
            const ocrStat = await stat(ocrPath);
            ocrCached = ocrStat.mtimeMs >= s.mtimeMs;
          }
          notes.push({
            path: full,
            name: noteName,
            modified: s.mtime,
            ocrCached,
            ocrPath,
            encrypted: true,
          });
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          // Skip config.sbc and non-note .sbe files
          if (!entry.name.includes("config")) {
            console.error(
              `[discovery] Could not decrypt filename ${entry.name}: ${msg}`,
            );
          }
        }
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
