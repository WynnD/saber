import { readFile } from "fs/promises";
import { discoverNotes, getDecryptionContext } from "./discovery.js";
import { decryptNote } from "../crypto.js";

export interface SearchResult {
  note: string;
  line: number;
  context: string;
}

/** Read OCR content, decrypting if the note is encrypted */
async function readOcrContent(
  ocrPath: string,
  encrypted: boolean,
): Promise<string> {
  const raw = await readFile(ocrPath);
  if (!encrypted) return raw.toString("utf-8");
  const ctx = await getDecryptionContext();
  if (!ctx) throw new Error("Decryption context not available");
  return decryptNote(raw, ctx).toString("utf-8");
}

export async function searchNotes(
  query: string,
  dir?: string,
  maxResults = 20,
): Promise<SearchResult[]> {
  const notes = await discoverNotes(dir);
  const results: SearchResult[] = [];
  const lowerQuery = query.toLowerCase();

  for (const note of notes) {
    if (!note.ocrCached) continue;
    if (results.length >= maxResults) break;

    const content = await readOcrContent(note.ocrPath, note.encrypted);
    const lines = content.split("\n");

    for (let i = 0; i < lines.length; i++) {
      if (results.length >= maxResults) break;
      if (!lines[i].toLowerCase().includes(lowerQuery)) continue;

      // 2 lines of context above and below
      const start = Math.max(0, i - 2);
      const end = Math.min(lines.length - 1, i + 2);
      const context = lines.slice(start, end + 1).join("\n");

      results.push({
        note: note.name,
        line: i + 1,
        context,
      });
    }
  }

  return results;
}
