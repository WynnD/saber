import { readFile } from "fs/promises";
import { discoverNotes } from "./discovery.js";

export interface SearchResult {
  note: string;
  line: number;
  context: string;
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

    const content = await readFile(note.ocrPath, "utf-8");
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
