// Client Graph API, classification des erreurs, et redaction des logs.

import { env, SECRET_VALUES } from "./env.ts";

const TIMEOUT_MS = 20_000;

// -----------------------------------------------------------------------------
// Redaction
// -----------------------------------------------------------------------------

/**
 * À passer sur TOUT ce qui part en log ou dans une colonne `last_error`.
 *
 * Trois filets, parce qu'un seul ne suffit jamais :
 *   1. les valeurs exactes de nos secrets ;
 *   2. la forme des tokens Meta (ils commencent tous par EAA) ;
 *   3. les paramètres d'URL qui en transportent.
 */
export function redact(input: unknown): string {
  let text = typeof input === "string" ? input : String(input);

  for (const secret of SECRET_VALUES) {
    if (secret && secret.length >= 8) {
      text = text.replaceAll(secret, "[secret]");
    }
  }

  text = text.replace(/EAA[A-Za-z0-9_-]{10,}/g, "[token]");
  text = text.replace(
    /\b(access_token|client_secret|fb_exchange_token|input_token|appsecret_proof)=[^&\s"']+/gi,
    "$1=[redacted]",
  );

  return text;
}

// -----------------------------------------------------------------------------
// Erreurs
// -----------------------------------------------------------------------------

export class GraphError extends Error {
  readonly code: number;
  readonly subcode: number | null;
  readonly type: string | null;
  readonly fbtraceId: string | null;
  readonly httpStatus: number;

  constructor(init: {
    message: string;
    code: number;
    subcode?: number | null;
    type?: string | null;
    fbtraceId?: string | null;
    httpStatus: number;
  }) {
    super(redact(init.message));
    this.name = "GraphError";
    this.code = init.code;
    this.subcode = init.subcode ?? null;
    this.type = init.type ?? null;
    this.fbtraceId = init.fbtraceId ?? null;
    this.httpStatus = init.httpStatus;
  }

  /** Forme compacte et sûre, destinée aux logs et à `last_error`. */
  describe(): string {
    const bits = [`code ${this.code}`];
    if (this.subcode) bits.push(`sous-code ${this.subcode}`);
    if (this.fbtraceId) bits.push(`trace ${this.fbtraceId}`);
    return `${this.message} (${bits.join(", ")})`;
  }
}

export type FailureKind =
  /** Le token est mort. Le commerçant doit refaire la connexion. */
  | "revoked"
  /** Panne passagère côté Meta ou quota. Réessayable tel quel. */
  | "transient"
  /** Le token va bien, c'est le contenu qui ne passe pas. */
  | "content";

/**
 * Codes qui signifient « ce token ne publiera plus jamais ».
 *
 *   190 — OAuthException : token révoqué, expiré, app désinstallée,
 *         mot de passe changé. Le cas nominal de la révocation.
 *    10 — l'app n'a pas la permission pour cette action.
 *   200 — erreur de permissions : typiquement le commerçant a perdu
 *         l'administration de sa Page, ou l'a transférée.
 *   102 — session invalide.
 *
 * Un token de Page n'a pas de date d'expiration : c'est par ces codes, et
 * uniquement par eux, qu'on apprend qu'il est mort.
 */
const REVOKED_CODES = new Set([102, 10, 190, 200]);

/** Pannes et quotas. On ne touche pas au statut du compte pour ceux-là. */
const TRANSIENT_CODES = new Set([1, 2, 4, 17, 32, 341, 368, 613]);

export function classify(error: unknown): FailureKind {
  if (!(error instanceof GraphError)) {
    // Réseau, timeout, JSON illisible : rien ne dit que le token est en cause.
    return "transient";
  }
  if (REVOKED_CODES.has(error.code)) return "revoked";
  if (TRANSIENT_CODES.has(error.code)) return "transient";
  if (error.httpStatus >= 500) return "transient";
  return "content";
}

// -----------------------------------------------------------------------------
// Appels
// -----------------------------------------------------------------------------

async function call(
  method: "GET" | "POST",
  path: string,
  options: {
    /** Pour GET : la query string. Pour POST : le corps urlencodé. */
    params?: Record<string, string | undefined>;
    /** Token de Page ou d'utilisateur. Part en en-tête, jamais en URL. */
    token?: string;
  } = {},
): Promise<Record<string, unknown>> {
  const clean = new URLSearchParams();
  for (const [key, value] of Object.entries(options.params ?? {})) {
    if (value !== undefined && value !== null && value !== "") {
      clean.set(key, value);
    }
  }

  const url = new URL(`${env.graphBase}/${path.replace(/^\//, "")}`);
  const headers: Record<string, string> = { Accept: "application/json" };
  let body: string | undefined;

  if (method === "GET") {
    url.search = clean.toString();
  } else {
    headers["Content-Type"] = "application/x-www-form-urlencoded";
    body = clean.toString();
  }

  // Le token voyage en en-tête, jamais en paramètre d'URL : une URL finit dans
  // les logs de la plateforme, un en-tête non.
  if (options.token) {
    headers["Authorization"] = `Bearer ${options.token}`;
  }

  let response: Response;
  try {
    response = await fetch(url, {
      method,
      headers,
      body,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (cause) {
    throw new GraphError({
      message: `Appel Graph injoignable : ${redact(cause)}`,
      code: -1,
      httpStatus: 0,
    });
  }

  const raw = await response.text();

  let payload: Record<string, unknown>;
  try {
    payload = raw ? JSON.parse(raw) : {};
  } catch {
    throw new GraphError({
      message: `Réponse Graph illisible : ${redact(raw).slice(0, 200)}`,
      code: -1,
      httpStatus: response.status,
    });
  }

  const err = payload.error as Record<string, unknown> | undefined;
  if (!response.ok || err) {
    throw new GraphError({
      message: String(err?.message ?? `HTTP ${response.status}`),
      code: Number(err?.code ?? -1),
      subcode: err?.error_subcode ? Number(err.error_subcode) : null,
      type: err?.type ? String(err.type) : null,
      fbtraceId: err?.fbtrace_id ? String(err.fbtrace_id) : null,
      httpStatus: response.status,
    });
  }

  return payload;
}

export const graph = {
  get: (path: string, params?: Record<string, string | undefined>, token?: string) =>
    call("GET", path, { params, token }),
  post: (path: string, params: Record<string, string | undefined>, token: string) =>
    call("POST", path, { params, token }),
};

// -----------------------------------------------------------------------------
// Échanges de tokens
// -----------------------------------------------------------------------------
// Les deux seuls appels où un secret transite en paramètre : l'endpoint
// /oauth/access_token l'exige, il n'y a pas d'alternative en en-tête. D'où
// redact() sur tout ce qui remonte de ces deux fonctions.

/** `code` reçu du dialogue → token utilisateur court (~1 h). */
export async function exchangeCodeForToken(code: string): Promise<string> {
  const data = await graph.get("oauth/access_token", {
    client_id: env.metaAppId,
    client_secret: env.metaAppSecret,
    redirect_uri: env.metaRedirectUri,
    code,
  });
  const token = data.access_token;
  if (typeof token !== "string") {
    throw new Error("Échange du code : aucun access_token dans la réponse.");
  }
  return token;
}

/**
 * Token court → token utilisateur longue durée (60 jours).
 *
 * Étape non négociable, et c'est l'erreur classique de ce flux : les tokens de
 * Page héritent de la durée de vie du token utilisateur qui les a produits.
 * Dérivés d'un token court, ils expirent en une heure. Dérivés d'un token
 * longue durée, ils n'expirent pas.
 */
export async function exchangeForLongLivedToken(
  shortLivedToken: string,
): Promise<string> {
  const data = await graph.get("oauth/access_token", {
    grant_type: "fb_exchange_token",
    client_id: env.metaAppId,
    client_secret: env.metaAppSecret,
    fb_exchange_token: shortLivedToken,
  });
  const token = data.access_token;
  if (typeof token !== "string") {
    throw new Error("Échange longue durée : aucun access_token dans la réponse.");
  }
  return token;
}

export interface TokenDebug {
  appId: string;
  scopes: string[];
  expiresAt: number | null;
}

/**
 * Inspecte un token. Sert à deux choses : récupérer les permissions réellement
 * accordées (le commerçant a pu en décocher dans le dialogue), et vérifier que
 * le token appartient bien à NOTRE app — garde contre un token substitué.
 */
export async function debugToken(token: string): Promise<TokenDebug> {
  const data = await graph.get("debug_token", {
    input_token: token,
    access_token: `${env.metaAppId}|${env.metaAppSecret}`,
  });

  const info = (data.data ?? {}) as Record<string, unknown>;
  const appId = String(info.app_id ?? "");

  if (appId !== env.metaAppId) {
    throw new Error(
      `Ce token appartient à l'application ${appId || "inconnue"}, ` +
        `pas à ${env.metaAppId}. Échange interrompu.`,
    );
  }

  const expiresAt = Number(info.expires_at ?? 0);

  return {
    appId,
    scopes: Array.isArray(info.scopes) ? (info.scopes as string[]) : [],
    // 0 signifie « n'expire pas » dans la réponse de Meta.
    expiresAt: expiresAt > 0 ? expiresAt : null,
  };
}

// -----------------------------------------------------------------------------
// Pages et comptes Instagram
// -----------------------------------------------------------------------------

export interface MetaPage {
  id: string;
  name: string;
  accessToken: string;
  avatarUrl: string | null;
  instagram: {
    id: string;
    username: string;
    avatarUrl: string | null;
  } | null;
}

/**
 * Liste les Pages du commerçant, leurs tokens de Page, et le compte Instagram
 * professionnel rattaché à chacune.
 *
 * À appeler avec le token utilisateur LONGUE DURÉE, pas le token court.
 */
export async function listPages(longLivedUserToken: string): Promise<MetaPage[]> {
  const fields = [
    "id",
    "name",
    "access_token",
    "picture{url}",
    "instagram_business_account{id,username,profile_picture_url}",
  ].join(",");

  const pages: MetaPage[] = [];
  let path: string | null = "me/accounts";
  let params: Record<string, string> | undefined = { fields, limit: "100" };

  // Un réseau peut administrer beaucoup de Pages : on suit la pagination.
  for (let page = 0; page < 10 && path; page++) {
    const data: Record<string, unknown> = await call("GET", path, {
      params,
      token: longLivedUserToken,
    });

    for (const raw of (data.data ?? []) as Record<string, unknown>[]) {
      const token = raw.access_token;
      // Une Page sans token de Page n'est pas administrable : on la saute
      // plutôt que de créer une ligne inutilisable.
      if (typeof token !== "string" || !token) continue;

      const ig = raw.instagram_business_account as
        | Record<string, unknown>
        | undefined;
      const picture = raw.picture as { data?: { url?: string } } | undefined;

      pages.push({
        id: String(raw.id),
        name: String(raw.name ?? "Page sans nom"),
        accessToken: token,
        avatarUrl: picture?.data?.url ?? null,
        instagram: ig?.id
          ? {
            id: String(ig.id),
            username: String(ig.username ?? "compte Instagram"),
            avatarUrl: ig.profile_picture_url
              ? String(ig.profile_picture_url)
              : null,
          }
          : null,
      });
    }

    const next = (data.paging as { next?: string } | undefined)?.next;
    if (!next) break;

    // L'URL `next` est absolue et porte déjà le curseur. On en extrait le
    // chemin pour rester sur notre client (en-tête d'autorisation, timeout).
    const nextUrl = new URL(next);
    path = nextUrl.pathname.replace(/^\/v\d+\.\d+\//, "");
    params = Object.fromEntries(nextUrl.searchParams);
    delete params.access_token;
  }

  return pages;
}
