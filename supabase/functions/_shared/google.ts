// Google Business Profile : OAuth, fiches (établissements) et posts « Offre ».
//
// Ce qu'on stocke : le REFRESH token Google, chiffré comme les tokens Meta
// (AES-256-GCM, clé hors base), lié à sa ligne par l'AAD
// « store_id|google_business|accounts/…/locations/… ». Le jeton d'accès, valable
// une heure, est redemandé à chaque publication et ne quitte jamais le worker.
//
// Secrets attendus (lus à l'usage, pour ne pas casser les fonctions Meta tant
// que Google n'est pas configuré) : GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
// GOOGLE_REDIRECT_URI (= …/functions/v1/google-oauth-callback).

export const GBP_SCOPE = "https://www.googleapis.com/auth/business.manage";

function secret(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new GoogleError(`${name} n'est pas configuré.`, "config");
  return v;
}

export const googleConfigured = () =>
  ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REDIRECT_URI"].every((n) => !!Deno.env.get(n));

/** revoked : reconnexion nécessaire. transient : on retentera. content : le post est refusé. */
export type GoogleErrorKind = "revoked" | "transient" | "content" | "config";

export class GoogleError extends Error {
  constructor(message: string, public kind: GoogleErrorKind) {
    super(message);
  }
}

export function authorizeUrl(state: string): string {
  const u = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  u.searchParams.set("client_id", secret("GOOGLE_CLIENT_ID"));
  u.searchParams.set("redirect_uri", secret("GOOGLE_REDIRECT_URI"));
  u.searchParams.set("response_type", "code");
  u.searchParams.set("scope", GBP_SCOPE);
  // offline + consent : garantit un refresh token, même en cas de reconnexion.
  u.searchParams.set("access_type", "offline");
  u.searchParams.set("prompt", "consent");
  u.searchParams.set("include_granted_scopes", "true");
  u.searchParams.set("state", state);
  return u.toString();
}

async function tokenCall(params: Record<string, string>): Promise<{ access_token: string; refresh_token?: string }> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: secret("GOOGLE_CLIENT_ID"),
      client_secret: secret("GOOGLE_CLIENT_SECRET"),
      ...params,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    // invalid_grant : refresh token révoqué ou expiré, le commerçant doit se reconnecter.
    const kind: GoogleErrorKind = data.error === "invalid_grant" ? "revoked" : res.status >= 500 ? "transient" : "content";
    throw new GoogleError(`Google OAuth : ${data.error ?? res.status} ${data.error_description ?? ""}`.trim(), kind);
  }
  return data;
}

export async function exchangeCode(code: string) {
  const t = await tokenCall({ code, grant_type: "authorization_code", redirect_uri: secret("GOOGLE_REDIRECT_URI") });
  if (!t.refresh_token) {
    throw new GoogleError("Google n'a pas fourni de jeton durable. Relancez la connexion.", "content");
  }
  return { accessToken: t.access_token, refreshToken: t.refresh_token };
}

export async function accessFromRefresh(refreshToken: string): Promise<string> {
  return (await tokenCall({ refresh_token: refreshToken, grant_type: "refresh_token" })).access_token;
}

async function gget(url: string, token: string) {
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw apiError(res.status, data);
  return data;
}

function apiError(status: number, data: { error?: { message?: string; status?: string } }) {
  const msg = `Google API ${status} : ${data?.error?.message ?? data?.error?.status ?? "erreur"}`;
  const kind: GoogleErrorKind = status === 401 || status === 403 ? "revoked" : status === 429 || status >= 500 ? "transient" : "content";
  return new GoogleError(msg, kind);
}

export interface GbpLocation {
  name: string; // accounts/{a}/locations/{l} : le chemin attendu par l'API des posts
  title: string;
  address: string;
  postalCode: string | null;
}

/** Toutes les fiches que le compte Google peut gérer. */
export async function listLocations(accessToken: string): Promise<GbpLocation[]> {
  const out: GbpLocation[] = [];
  const accounts = await gget("https://mybusinessaccountmanagement.googleapis.com/v1/accounts?pageSize=20", accessToken);
  for (const acc of accounts.accounts ?? []) {
    let page = "";
    do {
      const u = new URL(`https://mybusinessbusinessinformation.googleapis.com/v1/${acc.name}/locations`);
      u.searchParams.set("readMask", "name,title,storefrontAddress");
      u.searchParams.set("pageSize", "100");
      if (page) u.searchParams.set("pageToken", page);
      const r = await gget(u.toString(), accessToken);
      for (const l of r.locations ?? []) {
        const a = l.storefrontAddress ?? {};
        out.push({
          name: `${acc.name}/${l.name}`, // l.name = locations/{id}
          title: String(l.title ?? "Établissement"),
          address: [...(a.addressLines ?? []), [a.postalCode, a.locality].filter(Boolean).join(" ")].filter(Boolean).join(", "),
          postalCode: a.postalCode ?? null,
        });
      }
      page = r.nextPageToken ?? "";
    } while (page && out.length < 500);
  }
  return out;
}

const gdate = (iso: string) => {
  const d = new Date(iso);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() };
};

/**
 * Publie la promo en post « Offre » sur la fiche. Rend le nom du post créé.
 * Google limite le résumé à 1 500 caractères et le titre de l'offre à 58.
 */
export async function createOfferPost(
  accessToken: string,
  locationName: string,
  p: { title: string; summary: string; startsAt: string; endsAt: string; couponCode?: string | null; imageUrl?: string | null; url: string },
): Promise<string> {
  const body: Record<string, unknown> = {
    languageCode: "fr-FR",
    topicType: "OFFER",
    summary: p.summary.slice(0, 1500),
    event: { title: p.title.slice(0, 58), schedule: { startDate: gdate(p.startsAt), endDate: gdate(p.endsAt) } },
    offer: { redeemOnlineUrl: p.url, ...(p.couponCode ? { couponCode: p.couponCode.slice(0, 58) } : {}) },
  };
  if (p.imageUrl) body.media = [{ mediaFormat: "PHOTO", sourceUrl: p.imageUrl }];
  const res = await fetch(`https://mybusiness.googleapis.com/v4/${locationName}/localPosts`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw apiError(res.status, data);
  return String(data.name ?? "");
}
