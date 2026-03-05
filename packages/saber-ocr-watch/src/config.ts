import { homedir } from "os";
import { join } from "path";

export const config = {
  get notesDir(): string {
    return process.env.SABER_NOTES_DIR || join(homedir(), "Documents", "Saber");
  },
  get ollamaUrl(): string {
    return process.env.OLLAMA_URL || "http://localhost:11434";
  },
  get ollamaModel(): string {
    return process.env.OLLAMA_MODEL || "qwen3.5:9b";
  },
  get sbn2pdfCmd(): string {
    return process.env.SBN2PDF_CMD || "dart pub global run sbn2pdf";
  },
};
