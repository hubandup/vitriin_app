// google-pick — le commerçant choisit sa fiche Google quand son compte en gère plusieurs.
// Entrée : { store_id, location } (location = accounts/…/locations/…), JWT d'un membre du magasin.
// Le refresh token mis de côté par google-oauth-callback est rechiffré pour la fiche choisie.

import { accountAad, decryptToken, encryptToken, fromPgHex, KEY_VERSION, toPgHex } from "../_shared/crypto.ts";
import { fail, json, log, preflight } from "../_shared/http.ts";
import { authenticate, isStoreMember, serviceClient } from "../_shared/supabase.ts";
import { GBP_SCOPE } from "../_shared/google.ts";

const FN = "google-pick";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;
  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");
  const caller = await authenticate(req);
  if (!caller) return fail(req, 401, "Authentification requise.");

  let body: { store_id?: unknown; location?: unknown };
  try { body = await req.json(); } catch { return fail(req, 400, "Corps JSON invalide."); }
  const storeId = body.store_id, location = body.location;
  if (typeof storeId !== "string" || !UUID_RE.test(storeId)) return fail(req, 400, "store_id manquant ou mal formé.");
  if (typeof location !== "string" || !/^accounts\/[^/]+\/locations\/[^/]+$/.test(location)) return fail(req, 400, "Fiche invalide.");
  if (!await isStoreMember(caller, storeId)) return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");

  const service = serviceClient();
  const { data, error } = await service.rpc("google_pending_take", { p_store_id: storeId, p_user_id: caller.userId });
  const pending = Array.isArray(data) ? data[0] : data;
  if (error || !pending) return fail(req, 410, "Le choix a expiré. Relancez la connexion Google.");

  const loc = (pending.locations as { name: string; title: string }[]).find((l) => l.name === location);
  if (!loc) return fail(req, 400, "Cette fiche ne fait pas partie de votre compte Google.");

  try {
    const refresh = await decryptToken(fromPgHex(pending.cipher), accountAad(storeId, "google_business", "pending"));
    const cipher = await encryptToken(refresh, accountAad(storeId, "google_business", loc.name));
    const { error: upErr } = await service.rpc("social_account_upsert", {
      p_store_id: storeId, p_channel: "google_business", p_external_account_id: loc.name,
      p_display_name: loc.title, p_cipher: toPgHex(cipher), p_scopes: [GBP_SCOPE],
      p_connected_by: caller.userId, p_key_version: KEY_VERSION,
    });
    if (upErr) throw new Error(upErr.message);
    log("info", FN, "Fiche Google choisie", { storeId, userId: caller.userId });
    return json(req, { ok: true, display_name: loc.title });
  } catch (cause) {
    log("error", FN, "Enregistrement impossible", { storeId, detail: cause instanceof Error ? cause.message : String(cause) });
    return fail(req, 500, "Enregistrement impossible. Relancez la connexion Google.");
  }
});
