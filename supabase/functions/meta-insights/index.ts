// meta-insights — relit chez Meta les statistiques des publications d'un magasin.
//
// Entrée : { store_id, limit? }, avec le JWT d'un membre du magasin.
// Sortie : une ligne par publication réussie, avec ses chiffres normalisés.
//
// Les chiffres sont aussi écrits dans publications.metrics : l'app affiche les
// derniers chiffres connus sans rappeler Meta, et ne rafraîchit qu'à la demande.
//
// Autorisations Meta utilisées :
//   Facebook  · pages_read_engagement  → réactions, commentaires, partages
//             · read_insights          → portée et vues du post
//   Instagram · instagram_manage_insights → portée, vues, interactions
//
// Métriques choisies d'après l'état de l'API en octobre 2026 : les anciennes
// « impressions » ont été retirées (Instagram en avril 2025, Facebook en juin
// 2026) au profit des « vues ». Chaque métrique est demandée de façon tolérante :
// si Meta en refuse une, les autres sont quand même rendues.

import { preflight, fail, json, log } from "../_shared/http.ts";
import { graph, GraphError, redact } from "../_shared/meta.ts";
import {
  authenticate,
  isStoreMember,
  loadAccessToken,
  serviceClient,
} from "../_shared/supabase.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FN = "meta-insights";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

/** Statistiques normalisées, identiques pour les deux canaux. */
interface Metrics {
  reach: number | null;
  views: number | null;
  reactions: number | null;
  comments: number | null;
  shares: number | null;
  saved: number | null;
  interactions: number | null;
}

interface Account {
  id: string;
  store_id: string;
  channel: "facebook" | "instagram";
  external_account_id: string;
  parent_external_id: string | null;
  display_name: string;
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;
  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");

  const caller = await authenticate(req);
  if (!caller) return fail(req, 401, "Authentification requise.");

  let body: { store_id?: unknown; limit?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(req, 400, "Corps JSON invalide.");
  }

  const storeId = body.store_id;
  if (typeof storeId !== "string" || !UUID_RE.test(storeId)) {
    return fail(req, 400, "store_id manquant ou mal formé.");
  }

  const limit = Math.min(
    MAX_LIMIT,
    Math.max(1, Number.isInteger(body.limit) ? Number(body.limit) : DEFAULT_LIMIT),
  );

  // Lecture des statistiques : réservée aux membres du magasin, comme la
  // publication. Vérifié sous RLS avec le JWT de l'appelant.
  if (!await isStoreMember(caller, storeId)) {
    return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");
  }

  const service = serviceClient();

  // --- Les publications réussies du magasin --------------------------------
  const { data: rows, error: pubError } = await service
    .from("publications")
    .select(
      "id, channel, external_post_id, published_at, store_promotions!inner(store_id, promotions(title))",
    )
    .eq("store_promotions.store_id", storeId)
    .eq("status", "published")
    .in("channel", ["facebook", "instagram"])
    .not("external_post_id", "is", null)
    .order("published_at", { ascending: false })
    .limit(limit);

  if (pubError) {
    log("error", FN, "Lecture des publications impossible", {
      storeId,
      detail: pubError.message,
    });
    return fail(req, 500, "Erreur interne.");
  }

  // --- Les comptes actifs du magasin ---------------------------------------
  const { data: accounts, error: accError } = await service
    .from("social_accounts")
    .select("id, store_id, channel, external_account_id, parent_external_id, display_name")
    .eq("store_id", storeId)
    .eq("status", "active");

  if (accError) {
    log("error", FN, "Lecture des comptes impossible", {
      storeId,
      detail: accError.message,
    });
    return fail(req, 500, "Erreur interne.");
  }

  // Un token déchiffré par compte et par appel, pas un par publication.
  const tokens = new Map<string, Promise<string>>();
  const tokenFor = (account: Account) => {
    if (!tokens.has(account.id)) {
      tokens.set(account.id, loadAccessToken(service, account));
    }
    return tokens.get(account.id)!;
  };

  const revoked = new Set<string>();
  const now = new Date().toISOString();

  const results = await Promise.all(
    (rows ?? []).map(async (row) => {
      const channel = row.channel as "facebook" | "instagram";
      const postId = String(row.external_post_id);
      const sp = row.store_promotions as unknown as {
        promotions: { title: string } | null;
      };
      const base = {
        publication_id: row.id,
        channel,
        title: sp?.promotions?.title ?? null,
        published_at: row.published_at,
      };

      const account = pickAccount((accounts ?? []) as Account[], channel, postId);

      // Post publié sur une Page qui n'est plus celle du magasin (typiquement :
      // plusieurs Pages connectées un temps, puis une seule gardée). Il n'est
      // plus lisible avec les accès du magasin : on le masque durablement.
      if (!account && channel === "facebook") {
        await hide(service, row.id, "other_account", now);
        return { ...base, status: "hidden", reason: "other_account" };
      }
      if (!account || revoked.has(account.id)) {
        return { ...base, status: "unavailable", error: "Compte non connecté." };
      }

      try {
        const token = await tokenFor(account);
        const metrics = channel === "facebook"
          ? await facebookMetrics(postId, token)
          : await instagramMetrics(postId, token, account);

        await service
          .from("publications")
          .update({ metrics, metrics_fetched_at: now })
          .eq("id", row.id);

        return { ...base, status: "ok", account: account.display_name, metrics };
      } catch (cause) {
        if (cause instanceof Unreachable) {
          await hide(service, row.id, cause.reason, now);
          return { ...base, status: "hidden", reason: cause.reason };
        }

        const detail = cause instanceof GraphError
          ? cause.describe()
          : redact(cause instanceof Error ? cause.message : cause);

        // Seul le code 190 prouve qu'un token est mort. Les codes 10 et 200,
        // que classify() range aussi en « révoqué » pour la publication,
        // signifient ici « pas le droit de lire CE post » (post supprimé, ou
        // publié par un autre compte) : ils ne doivent pas déconnecter le
        // magasin.
        if (cause instanceof GraphError && cause.code === 190) {
          revoked.add(account.id);
          await markRevoked(service, account.id, detail);
        }

        log("warn", FN, "Statistiques indisponibles pour un post", {
          storeId,
          channel,
          detail,
        });
        return { ...base, status: "error", error: "Statistiques indisponibles pour ce post." };
      }
    }),
  );

  return json(req, {
    store_id: storeId,
    fetched_at: now,
    count: results.length,
    results,
  });
});

// -----------------------------------------------------------------------------
// Choix du compte
// -----------------------------------------------------------------------------
// publications ne garde pas l'identifiant du compte, seulement celui du post.
// Côté Facebook, l'identifiant d'un post commence par celui de sa Page
// (« pageId_postId ») : on retrouve la bonne Page même si le magasin en a
// plusieurs. Côté Instagram, un magasin n'a qu'un compte en pratique.

function pickAccount(
  accounts: Account[],
  channel: "facebook" | "instagram",
  postId: string,
): Account | undefined {
  const candidates = accounts.filter((a) => a.channel === channel);
  if (channel === "facebook") {
    // Correspondance stricte : jamais l'accès d'une autre Page. Meta refuserait
    // la lecture, et ce refus ne dit rien de l'état du compte.
    const pageId = postId.split("_")[0];
    return candidates.find((a) => a.external_account_id === pageId);
  }
  return candidates[0];
}

/**
 * Post qu'on ne pourra plus lire : supprimé depuis Facebook ou Instagram, ou
 * publié sur un autre compte que celui du magasin. Marqué dans metrics pour que
 * l'app le masque sans rappeler Meta à chaque fois.
 */
class Unreachable extends Error {
  constructor(readonly reason: "deleted" | "other_account") {
    super(reason);
  }
}

async function hide(
  service: SupabaseClient,
  publicationId: string,
  reason: string,
  now: string,
): Promise<void> {
  await service
    .from("publications")
    .update({ metrics: { hidden: true, reason }, metrics_fetched_at: now })
    .eq("id", publicationId);
}

/** Codes Meta signifiant « cet objet n'existe pas, ou pas pour ce token ». */
function isMissingObject(cause: unknown): boolean {
  return cause instanceof GraphError &&
    (cause.code === 100 || cause.code === 10 || cause.code === 803) &&
    /does not exist|cannot be loaded|Unsupported get request|n'existe pas/i
      .test(cause.message);
}

async function markRevoked(
  service: SupabaseClient,
  accountId: string,
  detail: string,
): Promise<void> {
  await service.rpc("social_account_set_status", {
    p_account_id: accountId,
    p_status: "revoked",
    p_error: detail,
  });
}

// -----------------------------------------------------------------------------
// Facebook
// -----------------------------------------------------------------------------

async function facebookMetrics(postId: string, token: string): Promise<Metrics> {
  // 1. Le post existe-t-il encore, et appartient-il à cette Page ?
  try {
    await graph.get(postId, { fields: "id" }, token);
  } catch (cause) {
    if (isMissingObject(cause)) throw new Unreachable("deleted");
    throw cause;
  }

  // 2. Engagement, un champ à la fois : Meta exige pour certains champs une
  //    autorisation que Vitriin ne demande pas (le compteur de commentaires
  //    réclame pages_read_user_content). Groupés, un seul refus ferait tout
  //    échouer ; séparés, on garde ce qui est lisible.
  const reactions = await fieldTolerant(
    postId,
    "reactions.summary(total_count).limit(0)",
    token,
    (post) => summaryCount(post.reactions),
  );
  const comments = await fieldTolerant(
    postId,
    "comments.summary(total_count).limit(0)",
    token,
    (post) => summaryCount(post.comments),
  );
  const shares = await fieldTolerant(
    postId,
    "shares",
    token,
    (post) => numberOr((post.shares as { count?: unknown } | undefined)?.count, 0),
  );

  // Portée et vues : Insights, avec read_insights. Meta n'en publie qu'après
  // quelques heures, et pas du tout sur les Pages trop petites : on tolère
  // l'absence plutôt que d'échouer.
  const insights = await insightsTolerant(postId, token, [
    "post_total_media_view_unique",
    "post_media_view",
  ]);

  return {
    reach: insights.post_total_media_view_unique ?? null,
    views: insights.post_media_view ?? null,
    reactions,
    comments,
    shares,
    saved: null,
    interactions: sumKnown(reactions, comments, shares),
  };
}

// -----------------------------------------------------------------------------
// Instagram
// -----------------------------------------------------------------------------

async function instagramMetrics(
  mediaId: string,
  token: string,
  account: Account,
): Promise<Metrics> {
  // Le média existe-t-il encore, et appartient-il au compte du magasin ?
  // publications ne garde pas le compte d'origine : on compare le nom du
  // compte propriétaire à celui connecté.
  let owner = "";
  try {
    const media = await graph.get(mediaId, { fields: "id,username" }, token);
    owner = String(media.username ?? "");
  } catch (cause) {
    if (isMissingObject(cause)) throw new Unreachable("deleted");
    throw cause;
  }
  if (owner && owner.toLowerCase() !== account.display_name.replace(/^@/, "").toLowerCase()) {
    throw new Unreachable("other_account");
  }

  const m = await insightsTolerant(mediaId, token, [
    "reach",
    "views",
    "likes",
    "comments",
    "shares",
    "saved",
    "total_interactions",
  ]);

  return {
    reach: m.reach ?? null,
    views: m.views ?? null,
    reactions: m.likes ?? null,
    comments: m.comments ?? null,
    shares: m.shares ?? null,
    saved: m.saved ?? null,
    interactions: m.total_interactions ??
      sumKnown(m.likes ?? null, m.comments ?? null, m.shares ?? null, m.saved ?? null),
  };
}

// -----------------------------------------------------------------------------
// Outils
// -----------------------------------------------------------------------------

/**
 * Demande toutes les métriques en un appel ; si Meta en refuse une (métrique
 * retirée, indisponible pour ce type de post), redemande une par une et garde
 * celles qui passent. Une erreur de token, elle, remonte immédiatement.
 */
async function insightsTolerant(
  objectId: string,
  token: string,
  metrics: string[],
): Promise<Record<string, number>> {
  try {
    return parseInsights(
      await graph.get(`${objectId}/insights`, { metric: metrics.join(",") }, token),
    );
  } catch (cause) {
    if (isDeadToken(cause)) throw cause;
  }

  const out: Record<string, number> = {};
  for (const metric of metrics) {
    try {
      Object.assign(
        out,
        parseInsights(await graph.get(`${objectId}/insights`, { metric }, token)),
      );
    } catch (cause) {
      if (isDeadToken(cause)) throw cause;
      // Métrique indisponible : on passe à la suivante.
    }
  }
  return out;
}

/** Lit un champ du post ; rend null si Meta le refuse (sauf token mort). */
async function fieldTolerant(
  postId: string,
  field: string,
  token: string,
  read: (post: Record<string, unknown>) => number,
): Promise<number | null> {
  try {
    return read(await graph.get(postId, { fields: field }, token));
  } catch (cause) {
    if (isDeadToken(cause)) throw cause;
    return null;
  }
}

function isDeadToken(cause: unknown): boolean {
  return cause instanceof GraphError && cause.code === 190;
}

function parseInsights(payload: Record<string, unknown>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const item of (payload.data ?? []) as Record<string, unknown>[]) {
    const name = String(item.name ?? "");
    const values = item.values as { value?: unknown }[] | undefined;
    const raw = values?.[0]?.value ?? (item.total_value as { value?: unknown })?.value;
    const value = typeof raw === "number" ? raw : Number(raw);
    if (name && Number.isFinite(value)) out[name] = value;
  }
  return out;
}

function summaryCount(edge: unknown): number {
  return numberOr(
    (edge as { summary?: { total_count?: unknown } } | undefined)?.summary?.total_count,
    0,
  );
}

function numberOr(value: unknown, fallback: number): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function sumKnown(...values: (number | null)[]): number | null {
  const known = values.filter((v): v is number => v !== null);
  return known.length ? known.reduce((a, b) => a + b, 0) : null;
}
