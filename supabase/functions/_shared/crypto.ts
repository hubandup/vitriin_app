// Chiffrement des tokens, et signature du paramètre `state` OAuth.
//
// AES-256-GCM via WebCrypto, clé dans TOKEN_ENCRYPTION_KEY (secret Supabase).
// Postgres ne voit que du bytea opaque et ne connaît jamais la clé : le
// déchiffrement en SQL est impossible par construction. Aucune policy, aucun
// GRANT ne peut être mal écrit au point d'exposer un token en clair via
// PostgREST — le chemin n'existe pas.
//
// GCM plutôt que CBC : c'est un mode authentifié. On lie chaque chiffré à sa
// ligne via l'AAD, donc un attaquant disposant d'un UPDATE ne peut pas recopier
// le token d'un magasin vers un autre pour publier en son nom.

import { env } from "./env.ts";

export const KEY_VERSION = 1;

const IV_BYTES = 12; // 96 bits, la taille recommandée pour GCM

let cachedKey: CryptoKey | null = null;

async function getKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;

  let raw: Uint8Array;
  try {
    raw = base64Decode(env.tokenEncryptionKey);
  } catch {
    throw new Error(
      "TOKEN_ENCRYPTION_KEY n'est pas du base64 valide. " +
        "Générer avec « openssl rand -base64 32 ».",
    );
  }

  if (raw.length !== 32) {
    throw new Error(
      `TOKEN_ENCRYPTION_KEY fait ${raw.length} octets, il en faut 32 (AES-256). ` +
        "Générer avec « openssl rand -base64 32 ».",
    );
  }

  cachedKey = await crypto.subtle.importKey(
    "raw",
    raw as BufferSource,
    { name: "AES-GCM" },
    false, // non exportable : la clé ne ressort pas du contexte WebCrypto
    ["encrypt", "decrypt"],
  );
  return cachedKey;
}

/**
 * Données additionnelles authentifiées : identifient la ligne à laquelle ce
 * chiffré appartient. Elles ne sont pas chiffrées, elles sont *liées* — si
 * l'une d'elles change, le déchiffrement échoue.
 */
export function accountAad(
  storeId: string,
  channel: string,
  externalAccountId: string,
): Uint8Array {
  return new TextEncoder().encode(`${storeId}|${channel}|${externalAccountId}`);
}

/** Rend `iv (12) || ciphertext || tag (16)`. */
export async function encryptToken(
  plaintext: string,
  aad: Uint8Array,
): Promise<Uint8Array> {
  const key = await getKey();
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));

  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: aad as BufferSource },
      key,
      new TextEncoder().encode(plaintext) as BufferSource,
    ),
  );

  const out = new Uint8Array(iv.length + sealed.length);
  out.set(iv, 0);
  out.set(sealed, iv.length);
  return out;
}

export async function decryptToken(
  blob: Uint8Array,
  aad: Uint8Array,
): Promise<string> {
  if (blob.length <= IV_BYTES + 16) {
    throw new Error("Chiffré trop court : donnée corrompue ou tronquée.");
  }

  const key = await getKey();
  const iv = blob.subarray(0, IV_BYTES);
  const sealed = blob.subarray(IV_BYTES);

  let opened: ArrayBuffer;
  try {
    opened = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv, additionalData: aad as BufferSource },
      key,
      sealed as BufferSource,
    );
  } catch {
    // GCM ne distingue pas « mauvaise clé » de « chiffré altéré » de « AAD qui
    // ne correspond pas » — et c'est voulu. Message volontairement neutre : on
    // ne renseigne pas un attaquant sur laquelle des trois a échoué.
    throw new Error(
      "Déchiffrement impossible. Causes possibles : TOKEN_ENCRYPTION_KEY a " +
        "changé, ou le chiffré ne correspond pas à cette ligne.",
    );
  }

  return new TextDecoder().decode(opened);
}

// -----------------------------------------------------------------------------
// Transport du bytea vers Postgres
// -----------------------------------------------------------------------------
// PostgREST sérialise un bytea en hexadécimal préfixé « \x », et accepte le
// même format en entrée. On évite le base64, ambigu selon le réglage
// `bytea_output` de la base.

export function toPgHex(bytes: Uint8Array): string {
  let hex = "";
  for (const b of bytes) hex += b.toString(16).padStart(2, "0");
  return `\\x${hex}`;
}

export function fromPgHex(value: string): Uint8Array {
  const hex = value.startsWith("\\x") ? value.slice(2) : value;
  if (hex.length === 0 || hex.length % 2 !== 0) {
    throw new Error("Chiffré illisible : hexadécimal mal formé.");
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) {
      throw new Error("Chiffré illisible : hexadécimal mal formé.");
    }
    out[i] = byte;
  }
  return out;
}

// -----------------------------------------------------------------------------
// Paramètre `state` OAuth
// -----------------------------------------------------------------------------
// Signé en HMAC-SHA256 : empêche la forge. Le nonce qu'il porte est consommé en
// base à usage unique : c'est lui, et pas la signature, qui empêche le rejeu.
// Les deux sont nécessaires.

export interface StatePayload {
  nonce: string;
  storeId: string;
  exp: number; // epoch en secondes
}

async function hmac(message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.metaStateSecret) as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(message) as BufferSource,
    ),
  );
}

export async function signState(payload: StatePayload): Promise<string> {
  const body = base64UrlEncode(
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  const sig = base64UrlEncode(await hmac(body));
  return `${body}.${sig}`;
}

/** Rend le payload si la signature et l'expiration tiennent, `null` sinon. */
export async function verifyState(state: string): Promise<StatePayload | null> {
  const parts = state.split(".");
  if (parts.length !== 2) return null;

  const [body, sig] = parts;

  let provided: Uint8Array;
  try {
    provided = base64UrlDecode(sig);
  } catch {
    return null;
  }

  const expected = await hmac(body);
  if (!timingSafeEqual(provided, expected)) return null;

  let payload: StatePayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(body)));
  } catch {
    return null;
  }

  if (
    typeof payload?.nonce !== "string" ||
    typeof payload?.storeId !== "string" ||
    typeof payload?.exp !== "number"
  ) {
    return null;
  }

  if (payload.exp < Math.floor(Date.now() / 1000)) return null;

  return payload;
}

export function randomNonce(): string {
  return base64UrlEncode(crypto.getRandomValues(new Uint8Array(32)));
}

/**
 * Comparaison à temps constant. Une comparaison `===` sort au premier octet
 * différent : le temps de réponse révélerait alors, octet par octet, la
 * signature attendue.
 */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  // On compare quand même les longueurs, mais sans court-circuiter la boucle :
  // la longueur d'une signature HMAC-SHA256 est publique (32 octets).
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// -----------------------------------------------------------------------------
// base64 / base64url
// -----------------------------------------------------------------------------

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  return base64Decode(padded + "=".repeat((4 - (padded.length % 4)) % 4));
}
