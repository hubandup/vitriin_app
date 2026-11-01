// google-oauth-start — ouvre l'autorisation Google Business Profile d'un magasin.
// Même schéma que meta-oauth-start : JWT du commerçant obligatoire, membre du
// magasin vérifié sous RLS, state signé (HMAC) + nonce consommé en base.
// Entrée : { store_id }. Sortie : { authorize_url }.

import { randomNonce, signState } from "../_shared/crypto.ts";
import { fail, json, log, preflight } from "../_shared/http.ts";
import { authenticate, isStoreMember, serviceClient } from "../_shared/supabase.ts";
import { authorizeUrl, googleConfigured } from "../_shared/google.ts";

const FN = "google-oauth-start";
const STATE_TTL_SECONDS = 600;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;
  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");
  if (!googleConfigured()) return fail(req, 503, "La connexion Google Business Profile arrive bientôt.");

  const caller = await authenticate(req);
  if (!caller) return fail(req, 401, "Authentification requise.");

  let storeId: unknown;
  try { storeId = (await req.json())?.store_id; } catch { return fail(req, 400, "Corps JSON invalide."); }
  if (typeof storeId !== "string" || !UUID_RE.test(storeId)) return fail(req, 400, "store_id manquant ou mal formé.");

  if (!await isStoreMember(caller, storeId)) {
    log("warn", FN, "Connexion refusée : non-membre", { storeId, userId: caller.userId });
    return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");
  }

  const nonce = randomNonce();
  const { error } = await serviceClient().rpc("oauth_state_create", {
    p_nonce: nonce, p_store_id: storeId, p_user_id: caller.userId, p_ttl_seconds: STATE_TTL_SECONDS,
  });
  if (error) {
    log("error", FN, "Écriture de l'état OAuth impossible", { storeId, detail: error.message });
    return fail(req, 500, "Impossible d'initialiser la connexion.");
  }

  const state = await signState({ nonce, storeId, exp: Math.floor(Date.now() / 1000) + STATE_TTL_SECONDS });
  log("info", FN, "Flux OAuth Google ouvert", { storeId, userId: caller.userId });
  return json(req, { authorize_url: authorizeUrl(state), expires_in: STATE_TTL_SECONDS });
});
