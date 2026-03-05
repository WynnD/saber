import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { discoverNotes, findNote, getDecryptionContext } from "./notes/discovery.js";
import { searchNotes } from "./notes/search.js";
import { readFile } from "fs/promises";
import { decryptNote } from "./crypto.js";

const server = new McpServer({
  name: "saber-notes",
  version: "0.1.0",
});

server.tool("list_notes", "List all Saber notes and their OCR cache status", {}, async () => {
  const notes = await discoverNotes();
  const items = notes.map((n) => ({
    name: n.name,
    path: n.path,
    ocrCached: n.ocrCached,
    lastModified: n.modified.toISOString(),
  }));
  return { content: [{ type: "text", text: JSON.stringify(items, null, 2) }] };
});

server.tool(
  "search_notes",
  "Search across all OCR'd Saber notes for matching text",
  { query: z.string().describe("Text to search for (case-insensitive)") },
  async ({ query }) => {
    const results = await searchNotes(query);
    if (results.length === 0) {
      return {
        content: [{ type: "text", text: `No matches found for "${query}".` }],
      };
    }
    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  },
);

server.tool(
  "get_note",
  "Get the full OCR'd text content of a specific Saber note",
  { name: z.string().describe("Note name (fuzzy matched)") },
  async ({ name }) => {
    const note = await findNote(name);
    if (!note) {
      return {
        content: [{ type: "text", text: `Note "${name}" not found.` }],
        isError: true,
      };
    }
    if (!note.ocrCached) {
      return {
        content: [
          {
            type: "text",
            text: `Note "${note.name}" exists but has no OCR cache. Run the watcher: saber-ocr-watch watch`,
          },
        ],
        isError: true,
      };
    }
    let content: string;
    if (note.encrypted) {
      const ctx = await getDecryptionContext();
      if (!ctx) return { content: [{ type: "text", text: "Decryption context not available" }], isError: true };
      const raw = await readFile(note.ocrPath);
      content = decryptNote(raw, ctx).toString("utf-8");
    } else {
      content = await readFile(note.ocrPath, "utf-8");
    }
    return {
      content: [{ type: "text", text: `# ${note.name}\n\n${content}` }],
    };
  },
);

export async function startServer(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

// Auto-start when run directly (for MCP config: node dist/index.js)
const isDirectRun = process.argv[1]?.endsWith("/index.js") || process.argv[1]?.endsWith("\\index.js");
if (isDirectRun) {
  startServer();
}
