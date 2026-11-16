const encoder = new TextEncoder();
const secret = Deno.env.get("PHONE_LOGIN_SECRET");

if (!secret || secret.length < 32) {
  throw new Error("PHONE_LOGIN_SECRET must contain at least 32 characters");
}

async function deriveKey(usage: "hmac" | "encrypt" | "decrypt") {
  const material = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    "HKDF",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode("strazh-phone-login-v1"),
      info: encoder.encode(`phone-login-${usage === "hmac" ? "hmac" : "aes"}`),
    },
    material,
    usage === "hmac"
      ? { name: "HMAC", hash: "SHA-256", length: 256 }
      : { name: "AES-GCM", length: 256 },
    false,
    usage === "hmac" ? ["sign"] : [usage],
  );
}

export async function hashLoginCode(code: string): Promise<string> {
  const key = await deriveKey("hmac");
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(code),
  );
  return toHex(new Uint8Array(signature));
}

export async function encryptLoginCode(code: string): Promise<string> {
  const key = await deriveKey("encrypt");
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce },
      key,
      encoder.encode(code),
    ),
  );
  return toBase64(concatBytes(nonce, ciphertext));
}

export async function decryptLoginCode(value: string): Promise<string> {
  const combined = fromBase64(value);
  const nonce = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  if (nonce.length !== 12 || ciphertext.length === 0) {
    throw new Error("Invalid encrypted phone login code");
  }
  const key = await deriveKey("decrypt");
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(plaintext);
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function concatBytes(first: Uint8Array, second: Uint8Array): Uint8Array {
  const result = new Uint8Array(first.length + second.length);
  result.set(first);
  result.set(second, first.length);
  return result;
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}
