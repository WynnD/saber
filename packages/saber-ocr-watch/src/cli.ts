#!/usr/bin/env node

import { startWatcher } from "./watcher/daemon.js";
import { startServer } from "./index.js";
import { ocrNote, type PdfExtractMode } from "./ocr/pipeline.js";
import { searchNotes } from "./notes/search.js";
import { findNote } from "./notes/discovery.js";
import { basename } from "path";

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case "watch":
    startWatcher();
    break;

  case "serve":
    startServer();
    break;

  case "ocr": {
    let pdfExtract: PdfExtractMode = "auto";
    const nameArgs: string[] = [];
    for (const a of args) {
      if (a === "--pdf-extract") pdfExtract = "force";
      else if (a === "--no-pdf-extract") pdfExtract = "never";
      else nameArgs.push(a);
    }
    const query = nameArgs.join(" ");
    if (!query) {
      console.error("Usage: saber-ocr-watch ocr [--pdf-extract|--no-pdf-extract] <note name>");
      process.exit(1);
    }
    const note = await findNote(query);
    if (!note) {
      console.error(`Note "${query}" not found`);
      process.exit(1);
    }
    console.error(`OCR'ing "${note.name}" (pdf-extract: ${pdfExtract})...`);
    const result = await ocrNote(note.path, { pdfExtract });
    const secs = (result.elapsed / 1000).toFixed(1);
    const method = result.pdfExtracted ? "pdftotext" : `vision OCR, ${result.pageCount} pages`;
    console.error(`Done: ${method}, ${secs}s → ${basename(result.ocrPath)}`);
    break;
  }

  case "search": {
    const query = args.join(" ");
    if (!query) {
      console.error("Usage: saber-ocr-watch search <query>");
      process.exit(1);
    }
    const results = await searchNotes(query);
    if (results.length === 0) {
      console.log(`No matches for "${query}"`);
    } else {
      for (const r of results) {
        console.log(`\n--- ${r.note} (line ${r.line}) ---`);
        console.log(r.context);
      }
    }
    break;
  }

  default:
    console.error(`Usage: saber-ocr-watch <command>

Commands:
  watch          Start file watcher daemon (foreground)
  serve          Start MCP server (stdio transport)
  ocr <note>     One-shot OCR of a specific note
                   --pdf-extract    Force pdftotext extraction (skip vision OCR)
                   --no-pdf-extract Force vision OCR (skip pdftotext)
                   (default: auto — uses pdftotext if note is PDF-only)
  search <query> Search across OCR'd notes`);
    process.exit(command ? 1 : 0);
}
