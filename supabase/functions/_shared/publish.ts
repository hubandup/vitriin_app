// Publication d'une activation sur les comptes connectés du magasin
// (Facebook, Instagram, Google Business Profile).
//
// Code commun à deux portes d'entrée, qui ne diffèrent que par l'autorisation :
//   • meta-publish      — le commerçant clique « Publier » (JWT, membre du magasin) ;
//   • publish-scheduled — l'heure programmée est arrivée (pg_cron). L'accord du
//     magasin a été donné en amont, par schedule_publication (membre vérifié).
// Ici on ne décide jamais QUI a le droit : on vérifie seulement que l'activation
// est publiable, puis on publie, canal par canal, isolés.

import { log } from "./http.ts";
import { classify, graph, GraphError, redact } from "./meta.ts";
import { loadAccessToken } from "./supabase.ts";
import { accessFromRefresh, createOfferPost, GoogleError } from "./google.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

/** Les canaux que l'on sait publier. L'enum en porte d'autres. */
export const PUBLISH_CHANNELS = ["facebook", "instagram", "google_business"] as const;
export type PublishChannel = (typeof PUBLISH_CHANNELS)[number];

// Vitrine publique (page de la promo côté client).
const VITRINE_URL = (Deno.env.get("PUBLIC_VITRINE_URL") ?? "https://app.vitriin.co/v").replace(/\/$/, "");

/** Limite de légende Instagram. Facebook est très au-dessus. */
const IG_CAPTION_MAX = 2_200;

/** Attente de la fabrication du container Instagram. */
const IG_POLL_MAX_MS = 45_000;
const IG_POLL_START_MS = 1_000;

interface SocialAccount {
  id: string;
  store_id: string;
  channel: PublishChannel;
  external_account_id: string;
  parent_external_id: string | null;
  display_name: string;
}

export interface ChannelReport {
  channel: PublishChannel;
  status: "published" | "failed" | "skipped";
  account: string | null;
  external_post_id?: string;
  error?: string;
}

export interface Activation {
  id: string;
  store_id: string;
  promotion_id: string;
  status: string;
  overrides: Record<string, unknown> | null;
  suspended: boolean;
  hidden: boolean;
}

export interface PublishReport {
  store_promotion_id: string;
  published: number;
  failed: number;
  results: ChannelReport[];
  message?: string;
}

/** Refus métier : l'activation n'est pas publiable. `status` = code HTTP. */
export class PublishRefused extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export async function loadActivation(
  service: SupabaseClient,
  storePromotionId: string,
): Promise<Activation | null> {
  const { data, error } = await service
    .from("store_promotions")
    .select("id, store_id, promotion_id, status, overrides, suspended, hidden")
    .eq("id", storePromotionId)
    .maybeSingle();
  if (error) throw new Error(`Lecture de l'activation impossible : ${error.message}`);
  return data as Activation | null;
}

/**
 * Publie l'activation sur les canaux demandés. Lève PublishRefused si elle
 * n'est pas publiable, Error sur une panne de lecture ; un canal qui échoue
 * n'est pas une exception, il figure dans le rapport.
 */
export async function publishActivation(
  service: SupabaseClient,
  activation: Activation,
  requested: PublishChannel[],
  fn: string,
): Promise<PublishReport> {
  const storePromotionId = activation.id;

  // --- L'activation est-elle relayée ? -------------------------------------
  // On ne publie pas une activation que le PDV n'a pas acceptée. Le verrou
  // is_mandatory du schéma garde tout son sens : une promo obligatoire naît
  // `active`, une promo optionnelle attend l'accord du commerçant.
  // Suspendue ou supprimée par le magasin : on ne publie pas.
  if (activation.suspended || activation.hidden) {
    throw new PublishRefused(409, "Cette promotion est suspendue ou supprimée sur ce point de vente.");
  }
  if (activation.status !== "active") {
    throw new PublishRefused(
      409,
      activation.status === "declined"
        ? "Ce point de vente a décliné cette promotion."
        : "Cette promotion n'a pas encore été activée par le point de vente.",
    );
  }

  // --- Le contenu ----------------------------------------------------------
  const { data: promotion, error: promotionError } = await service
    .from("promotions")
    .select("title, description, mechanic, media_url, discount_code, created_by_store_id, starts_at, ends_at, publish_at, publish_at_locked")
    .eq("id", activation.promotion_id)
    .maybeSingle();

  if (promotionError || !promotion) {
    throw new Error(`Lecture de la promotion impossible : ${promotionError?.message ?? "introuvable"}`);
  }

  // Date imposée par la centrale (MOD-082) : rien ne part avant. Le planificateur
  // passe à l'heure dite ; « Publier maintenant » est refusé jusque-là.
  if (promotion.publish_at_locked && promotion.publish_at &&
      new Date(promotion.publish_at as string).getTime() > Date.now() + 60_000) {
    const at = new Date(promotion.publish_at as string).toLocaleString("fr-FR", {
      timeZone: "Europe/Paris", weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
    });
    throw new PublishRefused(409, `Votre centrale a fixé la publication au ${at} : validez-la pour qu'elle parte à l'heure dite.`);
  }

  // Personnalisation du magasin (titre, texte, visuel), si sa centrale l'a
  // autorisée : le trigger guard_store_customization l'a déjà vérifié en base.
  const ov = (activation.overrides ?? {}) as Record<string, unknown>;
  const pick = (k: string) => typeof ov[k] === "string" && (ov[k] as string).trim() !== "" ? (ov[k] as string) : null;
  if (pick("title")) promotion.title = pick("title");
  if (pick("text")) promotion.description = pick("text");
  if (pick("media_url")?.startsWith("https://")) promotion.media_url = pick("media_url");

  const caption = buildCaption(promotion);
  const mediaUrl = typeof promotion.media_url === "string" &&
      promotion.media_url.startsWith("https://")
    ? promotion.media_url
    : null;

  // --- Les comptes connectés -----------------------------------------------
  const { data: accounts, error: accountsError } = await service
    .from("social_accounts")
    .select("id, store_id, channel, external_account_id, parent_external_id, display_name")
    .eq("store_id", activation.store_id)
    .eq("status", "active")
    // Le magasin peut couper un réseau dans ses Réglages sans le déconnecter.
    .eq("enabled", true)
    .in("channel", requested);

  if (accountsError) throw new Error(`Lecture des comptes impossible : ${accountsError.message}`);

  if (!accounts || accounts.length === 0) {
    return {
      store_promotion_id: storePromotionId,
      published: 0,
      failed: 0,
      results: [],
      message: "Aucun compte connecté et actif sur ce magasin pour les canaux demandés.",
    };
  }

  // --- Publier, canal par canal, isolés ------------------------------------
  const settled = await Promise.allSettled(
    (accounts as SocialAccount[]).map((account) =>
      publishToAccount(service, fn, {
        account,
        storePromotionId,
        // Facebook rend les liens cliquables : on ajoute la page de la promo
        // sur la vitrine Vitriin (code en caisse, itinéraire). Pas sur Instagram.
        caption: account.channel === "facebook"
          ? `${caption}\n\nEn profiter en magasin : ${VITRINE_URL}/p/${storePromotionId}`
          : caption,
        mediaUrl,
        offer: {
          title: String(promotion.title ?? "Promotion"),
          startsAt: promotion.starts_at as string,
          endsAt: promotion.ends_at as string,
          couponCode: typeof promotion.discount_code === "string" ? promotion.discount_code : null,
          url: `${VITRINE_URL}/p/${storePromotionId}`,
        },
      })
    ),
  );

  const results: ChannelReport[] = settled.map((outcome, index) => {
    if (outcome.status === "fulfilled") return outcome.value;

    // Filet : publishToAccount capture déjà ses erreurs. Si on arrive ici,
    // c'est un imprévu — on ne laisse pas le rapport incomplet pour autant.
    const account = (accounts as SocialAccount[])[index];
    return {
      channel: account.channel,
      status: "failed",
      account: account.display_name,
      error: redact(outcome.reason?.message ?? outcome.reason),
    };
  });

  const published = results.filter((r) => r.status === "published").length;
  const failed = results.filter((r) => r.status === "failed").length;

  log("info", fn, "Publication terminée", {
    storePromotionId,
    published,
    failed,
    skipped: results.filter((r) => r.status === "skipped").length,
  });

  return { store_promotion_id: storePromotionId, published, failed, results };
}

// -----------------------------------------------------------------------------
// Un compte
// -----------------------------------------------------------------------------

async function publishToAccount(
  service: SupabaseClient,
  fn: string,
  args: {
    account: SocialAccount;
    storePromotionId: string;
    caption: string;
    mediaUrl: string | null;
    offer: { title: string; startsAt: string; endsAt: string; couponCode: string | null; url: string };
  },
): Promise<ChannelReport> {
  const { account, storePromotionId, caption, mediaUrl, offer } = args;
  const base = { channel: account.channel, account: account.display_name };

  // Idempotence : un canal déjà publié n'est pas republié.
  const claim = await claimChannel(service, storePromotionId, account.channel);
  if (claim === "published") {
    return { ...base, status: "skipped", error: "Déjà publié sur ce canal." };
  }
  if (claim === "busy") {
    return {
      ...base,
      status: "skipped",
      error: "Une publication est déjà en cours sur ce canal.",
    };
  }

  try {
    const externalPostId = account.channel === "facebook"
      ? await publishToFacebook(service, account, caption, mediaUrl)
      : account.channel === "google_business"
      // Google : le refresh token chiffré donne un jeton d'une heure, jamais stocké.
      ? await createOfferPost(await accessFromRefresh(await loadAccessToken(service, account)), account.external_account_id,
        { ...offer, summary: caption, imageUrl: mediaUrl })
      : await publishToInstagram(service, account, caption, mediaUrl);

    await service
      .from("publications")
      .update({
        status: "published",
        external_post_id: externalPostId,
        error_message: null,
        published_at: new Date().toISOString(),
      })
      .eq("store_promotion_id", storePromotionId)
      .eq("channel", account.channel);

    return { ...base, status: "published", external_post_id: externalPostId };
  } catch (cause) {
    const message = redact(cause instanceof Error ? cause.message : cause);
    const detail = cause instanceof GraphError ? cause.describe() : message;

    // --- Le token est-il mort ? -------------------------------------------
    // Un token de Page n'a pas de date d'expiration : révocation, perte de
    // l'administration de la Page, changement de mot de passe ne se voient
    // qu'ici, par le code d'erreur. On marque le compte DANS LA TABLE, pour
    // que la centrale lise « ce point de vente n'est plus connecté » sans
    // avoir à déduire quoi que ce soit d'un échec de campagne.
    const kind = cause instanceof GoogleError ? cause.kind : classify(cause);
    if (kind === "revoked") {
      await service.rpc("social_account_set_status", {
        p_account_id: account.id,
        p_status: "revoked",
        p_error: detail,
      });
      log("warn", fn, "Compte marqué révoqué", {
        accountId: account.id,
        channel: account.channel,
        detail,
      });
    } else if (kind === "transient") {
      await service.rpc("social_account_set_status", {
        p_account_id: account.id,
        p_status: "error",
        p_error: detail,
      });
    }
    // kind === 'content' : le token va bien, c'est le contenu qui ne passe
    // pas. On ne touche surtout pas au statut du compte — une URL de visuel
    // cassée ne doit pas faire croire à une déconnexion.

    await service
      .from("publications")
      .update({ status: "failed", error_message: detail, published_at: null })
      .eq("store_promotion_id", storePromotionId)
      .eq("channel", account.channel);

    return { ...base, status: "failed", error: detail };
  }
}

/**
 * Réserve le canal, de façon atomique.
 *
 * `insert` d'abord : la contrainte unique (store_promotion_id, channel) en fait
 * une réservation exclusive. En cas de conflit, on tente de reprendre une ligne
 * `failed` ou `scheduled` — un UPDATE conditionnel sur le statut, donc atomique
 * lui aussi : deux exécutions du planificateur ne publient jamais deux fois.
 */
async function claimChannel(
  service: SupabaseClient,
  storePromotionId: string,
  channel: PublishChannel,
): Promise<"claimed" | "published" | "busy"> {
  const { error: insertError } = await service.from("publications").insert({
    store_promotion_id: storePromotionId,
    channel,
    status: "pending",
    claimed_at: new Date().toISOString(),
  });

  if (!insertError) return "claimed";

  // 23505 = violation d'unicité : la ligne existe déjà.
  if (insertError.code !== "23505") throw new Error(insertError.message);

  const { data: retaken } = await service
    .from("publications")
    .update({ status: "pending", error_message: null, claimed_at: new Date().toISOString() })
    .eq("store_promotion_id", storePromotionId)
    .eq("channel", channel)
    // Une ligne en échec, ou programmée : « Publier maintenant » passe avant la
    // programmation, et le planificateur reprend la sienne par ce même chemin.
    .in("status", ["failed", "scheduled"])
    .select("id")
    .maybeSingle();

  if (retaken) return "claimed";

  const { data: existing } = await service
    .from("publications")
    .select("status")
    .eq("store_promotion_id", storePromotionId)
    .eq("channel", channel)
    .maybeSingle();

  return existing?.status === "published" ? "published" : "busy";
}

// -----------------------------------------------------------------------------
// Facebook — un appel
// -----------------------------------------------------------------------------

async function publishToFacebook(
  service: SupabaseClient,
  account: SocialAccount,
  caption: string,
  mediaUrl: string | null,
): Promise<string> {
  const token = await loadAccessToken(service, account);
  const pageId = account.external_account_id;

  if (mediaUrl) {
    // Meta va chercher le fichier lui-même : l'URL doit être publiquement
    // joignable en HTTPS. Un bucket privé exige une URL signée.
    const data = await graph.post(
      `${pageId}/photos`,
      { url: mediaUrl, caption, published: "true" },
      token,
    );
    // `post_id` est l'identifiant du post dans le fil ; `id` est celui de la
    // photo. C'est le premier qu'on veut pour retrouver la publication.
    return String(data.post_id ?? data.id);
  }

  const data = await graph.post(`${pageId}/feed`, { message: caption }, token);
  return String(data.id);
}

// -----------------------------------------------------------------------------
// Instagram — container puis publication
// -----------------------------------------------------------------------------
// Mécanique imposée par Meta, et différente de Facebook : on crée d'abord un
// container média, Meta télécharge le visuel de son côté, puis on publie le
// container. Impossible de faire les deux en un appel.

async function publishToInstagram(
  service: SupabaseClient,
  account: SocialAccount,
  caption: string,
  mediaUrl: string | null,
): Promise<string> {
  if (!mediaUrl) {
    // Contrainte d'Instagram, pas de la nôtre : pas de post sans visuel.
    // Erreur de contenu, pas de token — le compte reste actif, et Facebook
    // publie quand même de son côté.
    throw new Error(
      "Instagram exige un visuel : cette promotion n'a pas de media_url en HTTPS.",
    );
  }

  const token = await loadAccessToken(service, account);
  const igUserId = account.external_account_id;

  // 1. Le container
  const container = await graph.post(
    `${igUserId}/media`,
    { image_url: mediaUrl, caption: caption.slice(0, IG_CAPTION_MAX) },
    token,
  );
  const creationId = String(container.id);

  // 2. Attendre que Meta ait récupéré le visuel
  await waitForContainer(creationId, token);

  // 3. Publier
  const published = await graph.post(
    `${igUserId}/media_publish`,
    { creation_id: creationId },
    token,
  );
  return String(published.id);
}

async function waitForContainer(
  creationId: string,
  token: string,
): Promise<void> {
  const deadline = Date.now() + IG_POLL_MAX_MS;
  let delay = IG_POLL_START_MS;

  while (Date.now() < deadline) {
    const data = await graph.get(
      creationId,
      { fields: "status_code,status" },
      token,
    );
    const code = String(data.status_code ?? "");

    if (code === "FINISHED") return;

    if (code === "ERROR" || code === "EXPIRED") {
      throw new Error(
        `Instagram n'a pas pu préparer le visuel (${code}). ` +
          `Vérifiez que l'URL est publiquement accessible en HTTPS, au format ` +
          `JPEG, et dans un ratio accepté. ${redact(String(data.status ?? ""))}`,
      );
    }

    await new Promise((resolve) => setTimeout(resolve, delay));
    delay = Math.min(delay * 1.5, 5_000);
  }

  throw new Error(
    "Instagram n'a pas fini de préparer le visuel dans le temps imparti. " +
      "Le visuel est peut-être trop lourd ; réessayez.",
  );
}

// -----------------------------------------------------------------------------
// Légende
// -----------------------------------------------------------------------------
function buildCaption(
  promotion: {
    title?: unknown;
    mechanic?: unknown;
    description?: unknown;
    discount_code?: unknown;
    created_by_store_id?: unknown;
  },
): string {
  const parts = [promotion.title, promotion.mechanic, promotion.description]
    .filter((p): p is string => typeof p === "string" && p.trim() !== "")
    .map((p) => p.trim());

  // Code de réduction en caisse. Fourni par la centrale pour une promo réseau.
  // Un code créé par le magasin doit être déclaré dans son logiciel de caisse :
  // la mention n'apparaît que dans l'app, jamais dans le post.
  // L'Espace Centrale l'écrit déjà dans le texte : on ne le répète pas.
  const code = typeof promotion.discount_code === "string"
    ? promotion.discount_code.trim()
    : "";
  if (code && !parts.some((p) => p.includes(code))) {
    parts.push(`Code en caisse : ${code}`);
  }

  return parts.join("\n\n");
}
