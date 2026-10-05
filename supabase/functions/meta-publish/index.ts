// meta-publish — publie une activation de promo sur les comptes connectés.
//
// Entrée : { store_promotion_id, channels? }, avec le JWT du commerçant.
// Sortie : un rapport par canal. Toujours 200 si la demande est valide, même
//          en cas d'échec partiel — un 500 global empêcherait le client de
//          distinguer « tout a raté » de « Instagram a raté ».
//
// Un canal qui échoue n'emporte pas les autres : chaque canal a sa ligne dans
// `publications`, son propre try/catch, et sa propre conclusion.

import { preflight, fail, json, log } from "../_shared/http.ts";
import {
  classify,
  graph,
  GraphError,
  redact,
} from "../_shared/meta.ts";
import {
  authenticate,
  isStoreMember,
  loadAccessToken,
  serviceClient,
} from "../_shared/supabase.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FN = "meta-publish";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Les canaux que cette fonction sait traiter. L'enum en porte d'autres. */
const META_CHANNELS = ["facebook", "instagram"] as const;
type MetaChannel = (typeof META_CHANNELS)[number];

/** Limite de légende Instagram. Facebook est très au-dessus. */
const IG_CAPTION_MAX = 2_200;

/** Attente de la fabrication du container Instagram. */
const IG_POLL_MAX_MS = 45_000;
const IG_POLL_START_MS = 1_000;

interface SocialAccount {
  id: string;
  store_id: string;
  channel: MetaChannel;
  external_account_id: string;
  parent_external_id: string | null;
  display_name: string;
}

interface ChannelReport {
  channel: MetaChannel;
  status: "published" | "failed" | "skipped";
  account: string | null;
  external_post_id?: string;
  error?: string;
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");

  const caller = await authenticate(req);
  if (!caller) return fail(req, 401, "Authentification requise.");

  // --- Entrée --------------------------------------------------------------
  let body: { store_promotion_id?: unknown; channels?: unknown };
  try {
    body = await req.json();
  } catch {
    return fail(req, 400, "Corps JSON invalide.");
  }

  const storePromotionId = body.store_promotion_id;
  if (typeof storePromotionId !== "string" || !UUID_RE.test(storePromotionId)) {
    return fail(req, 400, "store_promotion_id manquant ou mal formé.");
  }

  let requested: MetaChannel[] = [...META_CHANNELS];
  if (body.channels !== undefined) {
    if (
      !Array.isArray(body.channels) ||
      !body.channels.every((c) => META_CHANNELS.includes(c as MetaChannel))
    ) {
      return fail(
        req,
        400,
        `channels doit être un sous-ensemble de [${META_CHANNELS.join(", ")}].`,
      );
    }
    requested = body.channels as MetaChannel[];
  }

  const service = serviceClient();

  // --- L'activation --------------------------------------------------------
  const { data: activation, error: activationError } = await service
    .from("store_promotions")
    .select("id, store_id, promotion_id, status")
    .eq("id", storePromotionId)
    .maybeSingle();

  if (activationError) {
    log("error", FN, "Lecture de l'activation impossible", {
      detail: activationError.message,
    });
    return fail(req, 500, "Erreur interne.");
  }
  if (!activation) {
    // Même réponse que pour un accès refusé : ne pas révéler à un tiers
    // l'existence d'une activation qui ne le concerne pas.
    return fail(req, 404, "Activation introuvable.");
  }

  // --- Le droit de publier -------------------------------------------------
  // Membre du magasin, strictement. La centrale parente peut LIRE les
  // activations de ses PDV (policy store_promotions_select_members), mais
  // publier au nom d'un franchisé sur ses propres comptes sociaux est une
  // autre affaire : ça reste la main du magasin.
  if (!await isStoreMember(caller, activation.store_id)) {
    log("warn", FN, "Publication refusée : non-membre", {
      storePromotionId,
      userId: caller.userId,
    });
    return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");
  }

  // --- L'activation est-elle relayée ? -------------------------------------
  // On ne publie pas une activation que le PDV n'a pas acceptée. Le verrou
  // is_mandatory du schéma garde tout son sens : une promo obligatoire naît
  // `active`, une promo optionnelle attend l'accord du commerçant.
  if (activation.status !== "active") {
    return fail(
      req,
      409,
      activation.status === "declined"
        ? "Ce point de vente a décliné cette promotion."
        : "Cette promotion n'a pas encore été activée par le point de vente.",
    );
  }

  // --- Le contenu ----------------------------------------------------------
  const { data: promotion, error: promotionError } = await service
    .from("promotions")
    .select("title, description, mechanic, media_url")
    .eq("id", activation.promotion_id)
    .maybeSingle();

  if (promotionError || !promotion) {
    log("error", FN, "Lecture de la promotion impossible", {
      detail: promotionError?.message ?? "introuvable",
    });
    return fail(req, 500, "Erreur interne.");
  }

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
    .in("channel", requested);

  if (accountsError) {
    log("error", FN, "Lecture des comptes impossible", {
      detail: accountsError.message,
    });
    return fail(req, 500, "Erreur interne.");
  }

  if (!accounts || accounts.length === 0) {
    return json(req, {
      store_promotion_id: storePromotionId,
      published: 0,
      failed: 0,
      results: [],
      message:
        "Aucun compte connecté et actif sur ce magasin pour les canaux demandés.",
    });
  }

  // --- Publier, canal par canal, isolés ------------------------------------
  const settled = await Promise.allSettled(
    (accounts as SocialAccount[]).map((account) =>
      publishToAccount(service, {
        account,
        storePromotionId,
        caption,
        mediaUrl,
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

  log("info", FN, "Publication terminée", {
    storePromotionId,
    published,
    failed,
    skipped: results.filter((r) => r.status === "skipped").length,
  });

  return json(req, {
    store_promotion_id: storePromotionId,
    published,
    failed,
    results,
  });
});

// -----------------------------------------------------------------------------
// Un compte
// -----------------------------------------------------------------------------

async function publishToAccount(
  service: SupabaseClient,
  args: {
    account: SocialAccount;
    storePromotionId: string;
    caption: string;
    mediaUrl: string | null;
  },
): Promise<ChannelReport> {
  const { account, storePromotionId, caption, mediaUrl } = args;
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
    const kind = classify(cause);
    if (kind === "revoked") {
      await service.rpc("social_account_set_status", {
        p_account_id: account.id,
        p_status: "revoked",
        p_error: detail,
      });
      log("warn", FN, "Compte marqué révoqué", {
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
 * `failed` — un UPDATE conditionnel sur le statut, donc atomique lui aussi.
 */
async function claimChannel(
  service: SupabaseClient,
  storePromotionId: string,
  channel: MetaChannel,
): Promise<"claimed" | "published" | "busy"> {
  const { error: insertError } = await service.from("publications").insert({
    store_promotion_id: storePromotionId,
    channel,
    status: "pending",
  });

  if (!insertError) return "claimed";

  // 23505 = violation d'unicité : la ligne existe déjà.
  if (insertError.code !== "23505") throw new Error(insertError.message);

  const { data: retaken } = await service
    .from("publications")
    .update({ status: "pending", error_message: null })
    .eq("store_promotion_id", storePromotionId)
    .eq("channel", channel)
    .eq("status", "failed")
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
  promotion: { title?: unknown; mechanic?: unknown; description?: unknown },
): string {
  const parts = [promotion.title, promotion.mechanic, promotion.description]
    .filter((p): p is string => typeof p === "string" && p.trim() !== "")
    .map((p) => p.trim());

  return parts.join("\n\n");
}
