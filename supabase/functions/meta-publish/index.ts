// meta-publish — publie une activation de promo sur les comptes connectés
// (Facebook, Instagram et, depuis MOD-068, Google Business Profile).
//
// Entrée : { store_promotion_id, channels? }, avec le JWT du commerçant.
// Sortie : un rapport par canal. Toujours 200 si la demande est valide, même
//          en cas d'échec partiel — un 500 global empêcherait le client de
//          distinguer « tout a raté » de « Instagram a raté ».
//
// Cette porte ne fait que l'autorisation (membre du magasin). La publication
// elle-même vit dans _shared/publish.ts, partagée avec publish-scheduled
// (MOD-082). Une publication programmée sur ce canal est remplacée : « Publier
// maintenant » passe avant la programmation.

import { preflight, fail, json, log } from "../_shared/http.ts";
import { authenticate, isStoreMember, serviceClient } from "../_shared/supabase.ts";
import {
  loadActivation,
  publishActivation,
  PUBLISH_CHANNELS,
  PublishRefused,
  type PublishChannel,
} from "../_shared/publish.ts";

const FN = "meta-publish";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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

  let requested: PublishChannel[] = [...PUBLISH_CHANNELS];
  if (body.channels !== undefined) {
    if (
      !Array.isArray(body.channels) ||
      !body.channels.every((c) => PUBLISH_CHANNELS.includes(c as PublishChannel))
    ) {
      return fail(
        req,
        400,
        `channels doit être un sous-ensemble de [${PUBLISH_CHANNELS.join(", ")}].`,
      );
    }
    requested = body.channels as PublishChannel[];
  }

  const service = serviceClient();

  try {
    // --- L'activation ------------------------------------------------------
    const activation = await loadActivation(service, storePromotionId);
    if (!activation) {
      // Même réponse que pour un accès refusé : ne pas révéler à un tiers
      // l'existence d'une activation qui ne le concerne pas.
      return fail(req, 404, "Activation introuvable.");
    }

    // --- Le droit de publier -----------------------------------------------
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

    return json(req, await publishActivation(service, activation, requested, FN));
  } catch (cause) {
    if (cause instanceof PublishRefused) return fail(req, cause.status, cause.message);
    log("error", FN, "Publication impossible", {
      detail: cause instanceof Error ? cause.message : String(cause),
    });
    return fail(req, 500, "Erreur interne.");
  }
});
