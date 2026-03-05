import { homedir } from "os";
import { join } from "path";

export const config = {
  get notesDir(): string {
    return process.env.SABER_NOTES_DIR || join(homedir(), "Documents", "Saber");
  },
  get openaiUrl(): string {
    return process.env.OPENAI_BASE_URL || "http://localhost:11434";
  },
  get visionModel(): string {
    return process.env.VISION_MODEL || "qwen3.5:9b";
  },
  get sbn2pdfCmd(): string {
    return process.env.SBN2PDF_CMD || "dart pub global run sbn2pdf";
  },
  get encPassword(): string {
    return process.env.SABER_ENC_PASSWORD || "";
  },
};
