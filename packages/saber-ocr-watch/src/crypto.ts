import { createHash, createDecipheriv, createCipheriv } from "crypto";
import { readFile } from "fs/promises";
import { config } from "./config.js";

const SALT = "8MnPs64@R&mF8XjWeLrD";

interface SaberConfig {
  key: string; // base64 encrypted key
  iv: string; // base64 IV
}

/** Derive AES key from encryption password using Saber's scheme */
function derivePasswordKey(encPassword: string): Buffer {
  const input = encPassword + SALT;
  return createHash("sha256").update(input, "utf8").digest();
}

/**
 * Decrypt data using AES-SIC (CTR) mode.
 * Dart encrypt package default: AES-SIC with PKCS7 padding.
 */
function aesDecrypt(data: Buffer, key: Buffer, iv: Buffer): Buffer {
  const decipher = createDecipheriv("aes-256-ctr", key, iv);
  return Buffer.concat([decipher.update(data), decipher.final()]);
}

/** Strip PKCS7 padding from decrypted data */
function stripPkcs7(data: Buffer): Buffer {
  if (data.length === 0) return data;
  const padByte = data[data.length - 1];
  if (padByte < 1 || padByte > 16) return data;
  // Verify all padding bytes are the same
  for (let i = data.length - padByte; i < data.length; i++) {
    if (data[i] !== padByte) return data;
  }
  return data.subarray(0, data.length - padByte);
}

/** Load and parse Saber's config.sbc from the notes directory */
async function loadSaberConfig(): Promise<SaberConfig> {
  const configPath = config.notesDir + "/config.sbc";
  const raw = await readFile(configPath, "utf-8");
  return JSON.parse(raw) as SaberConfig;
}

export interface DecryptionContext {
  /** The actual AES key for decrypting note contents */
  noteKey: Buffer;
  /** The IV used for all encryption */
  iv: Buffer;
  /** Password-derived key (for decrypting file names) */
  passwordKey: Buffer;
}

/** Initialize decryption context from password + config.sbc */
export async function initDecryption(): Promise<DecryptionContext> {
  const encPassword = config.encPassword;
  if (!encPassword) {
    throw new Error(
      "SABER_ENC_PASSWORD not set — required for encrypted notes",
    );
  }

  const saberConfig = await loadSaberConfig();
  const passwordKey = derivePasswordKey(encPassword);
  const iv = Buffer.from(saberConfig.iv, "base64");

  // Decrypt the note key: config stores base64(AES(base64(realKey)))
  const encryptedKey = Buffer.from(saberConfig.key, "base64");
  const decryptedKeyB64 = aesDecrypt(encryptedKey, passwordKey, iv).toString(
    "utf-8",
  );
  const noteKey = Buffer.from(decryptedKeyB64, "base64");

  return { noteKey, iv, passwordKey };
}

/** Decrypt a .sbe file's contents into raw .sbn2 BSON bytes */
export function decryptNote(
  encrypted: Buffer,
  ctx: DecryptionContext,
): Buffer {
  // Saber uses the password-derived key (client.encrypter) for both
  // file names and file contents
  return stripPkcs7(aesDecrypt(encrypted, ctx.passwordKey, ctx.iv));
}

/** Decrypt an encrypted file name (hex-encoded) back to original path */
export function decryptFileName(
  encryptedHex: string,
  ctx: DecryptionContext,
): string {
  const encrypted = Buffer.from(encryptedHex, "hex");
  const decrypted = stripPkcs7(aesDecrypt(encrypted, ctx.passwordKey, ctx.iv));
  return decrypted.toString("utf-8");
}

/** Encrypt data using the password key (matching Saber's client.encrypter) */
export function encryptNote(
  data: Buffer,
  ctx: DecryptionContext,
): Buffer {
  const cipher = createCipheriv("aes-256-ctr", ctx.passwordKey, ctx.iv);
  return Buffer.concat([cipher.update(data), cipher.final()]);
}

/** Encrypt a path to match Saber's file naming (for lookups) */
export function encryptPath(
  path: string,
  ctx: DecryptionContext,
): string {
  const cipher = createCipheriv("aes-256-ctr", ctx.passwordKey, ctx.iv);
  const encrypted = Buffer.concat([
    cipher.update(path, "utf-8"),
    cipher.final(),
  ]);
  return encrypted.toString("hex");
}
