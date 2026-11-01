// google-oauth-callback — retour de Google après autorisation. PUBLIQUE (Google
// redirige le navigateur ici, sans JWT) : la confiance repose sur le state signé
// et son nonce consommé une seule fois.
//
// Une fiche se choisit ainsi : celle dont le code postal est celui du magasin,
// sinon la seule fiche du compte. Sinon (plusieurs fiches), le refresh token est
// mis de côté chiffré 15 minutes et le commerçant choisit dans l'app (google-pick).

import { accountAad, encryptToken, KEY_VERSION, toPgHex, verifyState } from "../_shared/crypto.ts";
import { confirmationPage, log } from "../_shared/http.ts";
import { redact } from "../_shared/meta.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { exchangeCode, GBP_SCOPE, listLocations } from "../_shared/google.ts";

const FN = "google-oauth-callback";

const page = (ok: boolean, title: string, message: string, accounts: string[] = [], status?: number) =>
  confirmationPage({ ok, title, message, accounts, status });

Deno.serve(async (req) => {
  const params = new URL(req.url).searchParams;
  if (params.get("error")) {
    return page(false, "Connexion annulée", "Vous avez refusé l'autorisation Google, ou la fenêtre a été fermée. Aucune fiche n'a été connectée.", [], 200);
  }
  const code = params.get("code"), state = params.get("state");
  if (!code || !state) return page(false, "Lien incomplet", "Cette adresse ne contient pas les paramètres attendus.");

  const payload = await verifyState(state);
  if (!payload) return page(false, "Lien expiré", "Ce lien de connexion n'est plus valable (dix minutes maximum). Relancez la connexion depuis l'application.");

  const service = serviceClient();
  const { data: consumed, error: consumeError } = await service.rpc("oauth_state_consume", { p_nonce: payload.nonce });
  const row = Array.isArray(consumed) ? consumed[0] : consumed;
  if (consumeError || !row || row.store_id !== payload.storeId) {
    return page(false, "Lien déjà utilisé", "Ce lien de connexion a déjà servi, ou il a expiré. Relancez la connexion depuis l'application.");
  }
  const storeId: string = row.store_id, userId: string = row.user_id;

  try {
    const { accessToken, refreshToken } = await exchangeCode(code);
    const locations = await listLocations(accessToken);
    if (!locations.length) {
      return page(false, "Aucune fiche trouvée", "Ce compte Google ne gère aucune fiche d'établissement. Connectez-vous avec le compte propriétaire ou gestionnaire de la fiche du magasin.", [], 200);
    }

    const { data: store } = await service.from("stores").select("postal_code").eq("id", storeId).maybeSingle();
    const byPostal = store?.postal_code ? locations.filter((l) => l.postalCode === store.postal_code) : [];
    const chosen = byPostal.length === 1 ? byPostal[0] : locations.length === 1 ? locations[0] : null;

    if (!chosen) {
      // Plusieurs fiches possibles : le commerçant choisit dans l'app.
      const cipher = await encryptToken(refreshToken, accountAad(storeId, "google_business", "pending"));
      const { error } = await service.rpc("google_pending_put", {
        p_store_id: storeId, p_user_id: userId, p_cipher: toPgHex(cipher),
        p_locations: locations.map(({ name, title, address }) => ({ name, title, address })),
      });
      if (error) throw new Error(error.message);
      const ret = Deno.env.get("APP_RETURN_URL");
      if (ret) {
        const target = new URL(ret);
        target.searchParams.set("oauth", "gbp-pick");
        return new Response(null, { status: 302, headers: { Location: target.toString(), "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } });
      }
      return page(true, "Choisissez votre fiche", "Revenez dans l'application Vitriin pour choisir la fiche Google de votre magasin.");
    }

    const cipher = await encryptToken(refreshToken, accountAad(storeId, "google_business", chosen.name));
    const { error } = await service.rpc("social_account_upsert", {
      p_store_id: storeId, p_channel: "google_business", p_external_account_id: chosen.name,
      p_display_name: chosen.title, p_cipher: toPgHex(cipher), p_scopes: [GBP_SCOPE],
      p_connected_by: userId, p_key_version: KEY_VERSION,
    });
    if (error) throw new Error(error.message);
    log("info", FN, "Fiche Google connectée", { storeId, userId });
    return page(true, "Fiche Google connectée", "Votre fiche Google est connectée à Vitriin. Vos promotions pourront y être publiées.", [chosen.title]);
  } catch (cause) {
    log("error", FN, "Échec du flux OAuth Google", { storeId, detail: redact(cause instanceof Error ? cause.message : cause) });
    return page(false, "Connexion impossible", "La connexion à Google a échoué. Réessayez dans un instant ; si le problème persiste, contactez le support.", [], 500);
  }
});
