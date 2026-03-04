import { readFile } from "fs/promises";
import { config } from "../config.js";

const OCR_PROMPT =
  "Transcribe all text visible in this image. Return only the transcribed text, preserving line breaks and layout. If there is no text, respond with [no text].";

interface ChatCompletionResponse {
  choices: Array<{ message: { content: string } }>;
}

export async function ocrImage(imagePath: string): Promise<string> {
  const imageData = await readFile(imagePath);
  const base64 = imageData.toString("base64");

  const resp = await fetch(`${config.ollamaUrl}/v1/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: config.ollamaModel,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: OCR_PROMPT },
            {
              type: "image_url",
              image_url: { url: `data:image/png;base64,${base64}` },
            },
          ],
        },
      ],
      temperature: 0,
      chat_template_kwargs: { enable_thinking: false },
    }),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Ollama error ${resp.status}: ${text}`);
  }

  const data = (await resp.json()) as ChatCompletionResponse;
  return data.choices[0].message.content.trim();
}
