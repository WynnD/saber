import { readFile } from "fs/promises";
import { config } from "../config.js";

const OCR_PROMPT =
  "Transcribe everything visible in this handwritten note. Use markdown.";

interface ChatCompletionResponse {
  choices: Array<{ message: { content: string } }>;
}

export async function ocrImage(imagePath: string): Promise<string> {
  const imageData = await readFile(imagePath);
  const base64 = imageData.toString("base64");

  const resp = await fetch(`${config.openaiUrl}/v1/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: config.visionModel,
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
    throw new Error(`Vision API error ${resp.status}: ${text}`);
  }

  const data = (await resp.json()) as ChatCompletionResponse;
  return data.choices[0].message.content.trim();
}
