/**
 * Extract plain text from quill delta ops.
 * Each op is { insert: string | object, attributes?: ... }.
 * We only care about string inserts.
 */
export function extractQuillText(delta: unknown[]): string {
  const parts: string[] = [];
  for (const op of delta) {
    if (op && typeof op === "object" && "insert" in op) {
      const insert = (op as { insert: unknown }).insert;
      if (typeof insert === "string") {
        parts.push(insert);
      }
    }
  }
  return parts.join("").trim();
}
