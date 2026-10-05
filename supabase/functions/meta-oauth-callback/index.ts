// meta-oauth-callback — reçoit le retour de Meta, stocke les comptes.
//
//   URL : https://zjugauidrijghesgsmap.supabase.co/functions/v1/meta-oauth-callback
//
// S'exécute SANS JWT (verify_jwt = false dans config.toml) : c'est Meta qui
// redirige ici le navigateur du commerçant, et un navigateur ne sait pas poser
// d'en-tête Authorization. Toute la sécurité repose donc sur le `state` : signé
// en HMAC contre la forge, adossé à un nonce consommé en base contre le rejeu.
//
// Répond en HTML, pas en JSON : un humain regarde cette page.

import {
  accountAad,
  encryptToken,
  KEY_VERSION,
  toPgHex,
  verifyState,
} from "../_shared/crypto.ts";
import { confirmationPage, log } from "../_shared/http.ts";
import {
  debugToken,
  exchangeCodeForToken,
  exchangeForLongLivedToken,
  listPages,
  type MetaPage,
  redact,
} from "../_shared/meta.ts";
import { serviceClient } from "../_shared/supabase.ts";

const FN = "meta-oauth-callback";

Deno.serve(async (req) => {
  const params = new URL(req.url).searchParams;

  // --- Le commerçant a annulé ----------------------------------------------
  // Cas nominal, pas une panne : on lui rend une page lisible, pas une 500.
  const oauthError = params.get("error");
  if (oauthError) {
    log("info", FN, "Autorisation refusée par l'utilisateur", {
      reason: params.get("error_reason") ?? oauthError,
    });
    return confirmationPage({
      ok: false,
      title: "Connexion annulée",
      message:
        "Vous avez refusé l'autorisation, ou la fenêtre a été fermée avant la fin. " +
        "Aucun compte n'a été connecté. Vous pouvez relancer la connexion depuis l'application.",
      status: 200,
    });
  }

  const code = params.get("code");
  const state = params.get("state");

  if (!code || !state) {
    return confirmationPage({
      ok: false,
      title: "Lien incomplet",
      message: "Cette adresse ne contient pas les paramètres attendus.",
    });
  }

  // --- Vérifier le state ---------------------------------------------------
  // 1. La signature : le state vient bien de nous et n'a pas été modifié.
  const payload = await verifyState(state);
  if (!payload) {
    log("warn", FN, "State invalide ou expiré");
    return confirmationPage({
      ok: false,
      title: "Lien expiré",
      message:
        "Ce lien de connexion n'est plus valable. Les liens expirent au bout de " +
        "dix minutes, par sécurité. Relancez la connexion depuis l'application.",
    });
  }

  // 2. Le nonce : consommé en base, donc utilisable UNE fois. C'est ce DELETE,
  //    et pas la signature, qui empêche le rejeu d'un state intercepté.
  const service = serviceClient();
  const { data: consumed, error: consumeError } = await service.rpc(
    "oauth_state_consume",
    { p_nonce: payload.nonce },
  );

  const stateRow = Array.isArray(consumed) ? consumed[0] : consumed;

  if (consumeError || !stateRow) {
    log("warn", FN, "State déjà consommé ou expiré", {
      detail: consumeError?.message ?? "aucune ligne",
    });
    return confirmationPage({
      ok: false,
      title: "Lien déjà utilisé",
      message:
        "Ce lien de connexion a déjà servi, ou il a expiré. " +
        "Relancez la connexion depuis l'application.",
    });
  }

  // 3. Cohérence : le magasin signé dans le state doit être celui de la ligne.
  //    Les deux viennent de nous, donc un écart signifie une incohérence
  //    sérieuse — on s'arrête.
  if (stateRow.store_id !== payload.storeId) {
    log("error", FN, "Incohérence entre le state signé et l'état en base", {
      storeId: payload.storeId,
    });
    return confirmationPage({
      ok: false,
      title: "Connexion refusée",
      message: "Une incohérence a été détectée. La connexion a été interrompue.",
    });
  }

  const storeId: string = stateRow.store_id;
  const userId: string = stateRow.user_id;

  try {
    // --- Les deux échanges de tokens ---------------------------------------
    const shortLived = await exchangeCodeForToken(code);

    // L'ordre compte : les tokens de Page héritent de la durée de vie du token
    // utilisateur qui les produit. Dérivés du token court, ils expireraient en
    // une heure. Dérivés du token longue durée, ils n'expirent pas.
    const longLived = await exchangeForLongLivedToken(shortLived);

    // Vérifie que le token est bien émis pour NOTRE app, et récupère les
    // permissions réellement accordées — le commerçant a pu en décocher.
    const debug = await debugToken(longLived);

    // --- Les Pages, et leurs comptes Instagram -----------------------------
    const pages = await listPages(longLived);

    if (pages.length === 0) {
      log("warn", FN, "Aucune Page administrable", { storeId });
      return confirmationPage({
        ok: false,
        title: "Aucune Page trouvée",
        message:
          "Votre compte Facebook n'administre aucune Page, ou aucune Page n'a été " +
          "cochée pendant l'autorisation. Vérifiez que vous êtes bien administrateur " +
          "d'une Page, puis relancez la connexion.",
        status: 200,
      });
    }

    const connected: string[] = [];

    for (const page of pages) {
      // Une Page qui échoue ne doit pas emporter les autres.
      try {
        connected.push(...await storePage(service, {
          page,
          storeId,
          userId,
          scopes: debug.scopes,
        }));
      } catch (cause) {
        log("error", FN, "Enregistrement d'une Page impossible", {
          storeId,
          pageId: page.id,
          detail: redact(cause instanceof Error ? cause.message : cause),
        });
      }
    }

    // --- Le token utilisateur longue durée s'arrête ici ---------------------
    // Il n'est écrit nulle part. Il porte business_management et permet
    // d'énumérer tout le patrimoine Business du commerçant ; les tokens de Page
    // qu'on conserve ne publient que sur leur propre Page. En cas de fuite,
    // l'écart est considérable. Il sort de portée avec cette fonction.

    if (connected.length === 0) {
      return confirmationPage({
        ok: false,
        title: "Enregistrement impossible",
        message:
          "Les Pages ont bien été autorisées, mais leur enregistrement a échoué. " +
          "Réessayez dans un instant.",
        status: 500,
      });
    }

    log("info", FN, "Comptes connectés", {
      storeId,
      userId,
      count: connected.length,
      scopes: debug.scopes.join(","),
    });

    return confirmationPage({
      ok: true,
      title: "Comptes connectés",
      message: connected.length === 1
        ? "Votre compte est connecté à Vitriin. Vous pouvez maintenant publier vos promotions dessus."
        : `${connected.length} comptes sont connectés à Vitriin. Vous pouvez maintenant publier vos promotions dessus.`,
      accounts: connected,
    });
  } catch (cause) {
    const detail = redact(cause instanceof Error ? cause.message : cause);
    log("error", FN, "Échec du flux OAuth", { storeId, detail });

    return confirmationPage({
      ok: false,
      title: "Connexion impossible",
      message:
        "La connexion à Meta a échoué. Réessayez dans un instant ; si le problème " +
        "persiste, contactez le support.",
      status: 500,
    });
  }
});

/**
 * Enregistre une Page et, le cas échéant, son compte Instagram professionnel.
 * Rend les noms affichables des comptes écrits.
 *
 * Deux lignes distinctes pour le MÊME token : le compte Instagram n'a pas de
 * token propre dans ce flux, il publie avec le token de sa Page porteuse. On
 * chiffre donc deux fois la même valeur — chaque chiffré est lié à sa ligne par
 * son AAD, et recopier l'un sur l'autre ne déchiffrerait pas.
 */
async function storePage(
  service: ReturnType<typeof serviceClient>,
  args: { page: MetaPage; storeId: string; userId: string; scopes: string[] },
): Promise<string[]> {
  const { page, storeId, userId, scopes } = args;
  const written: string[] = [];

  const upsert = async (fields: {
    channel: "facebook" | "instagram";
    externalAccountId: string;
    displayName: string;
    avatarUrl: string | null;
    parentExternalId: string | null;
  }) => {
    const cipher = await encryptToken(
      page.accessToken,
      accountAad(storeId, fields.channel, fields.externalAccountId),
    );

    const { error } = await service.rpc("social_account_upsert", {
      p_store_id: storeId,
      p_channel: fields.channel,
      p_external_account_id: fields.externalAccountId,
      p_display_name: fields.displayName,
      p_cipher: toPgHex(cipher),
      p_parent_external_id: fields.parentExternalId,
      p_avatar_url: fields.avatarUrl,
      p_scopes: scopes,
      p_connected_by: userId,
      p_key_version: KEY_VERSION,
      // Un token de Page n'expire pas tant que le commerçant ne révoque pas.
      p_token_expires_at: null,
    });

    if (error) throw new Error(error.message);
  };

  await upsert({
    channel: "facebook",
    externalAccountId: page.id,
    displayName: page.name,
    avatarUrl: page.avatarUrl,
    parentExternalId: null,
  });
  written.push(`${page.name} · Facebook`);

  if (page.instagram) {
    await upsert({
      channel: "instagram",
      externalAccountId: page.instagram.id,
      displayName: page.instagram.username,
      avatarUrl: page.instagram.avatarUrl,
      parentExternalId: page.id,
    });
    written.push(`@${page.instagram.username} · Instagram`);
  }

  return written;
}
