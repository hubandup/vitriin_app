// meta-oauth-start — ouvre le flux d'autorisation Facebook Login for Business.
//
// Entrée  : { store_id }, avec le JWT du commerçant.
// Sortie  : { authorize_url }, ou une 302 si ?redirect=1.
//
// Pourquoi du JSON et pas une redirection par défaut : cette fonction est en
// verify_jwt = true, donc tout appel doit porter un en-tête Authorization —
// qu'une navigation navigateur ne sait pas poser. L'app récupère donc l'URL,
// puis l'ouvre dans un navigateur in-app. C'est ce parcours-là qu'on filme
// pour l'App Review.
//
// ?redirect=1 renvoie une 302 plutôt que du JSON, pour un client qui préfère
// suivre la redirection lui-même. Ça ne permet PAS de coller l'adresse dans
// une barre d'URL : le JWT reste obligatoire.

import { randomNonce, signState } from "../_shared/crypto.ts";
import { env } from "../_shared/env.ts";
import { fail, json, log, preflight } from "../_shared/http.ts";
import { authenticate, isStoreMember, serviceClient } from "../_shared/supabase.ts";

const FN = "meta-oauth-start";
const STATE_TTL_SECONDS = 600;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  if (req.method !== "POST" && req.method !== "GET") {
    return fail(req, 405, "Méthode non autorisée.");
  }

  // --- Qui appelle ---------------------------------------------------------
  const caller = await authenticate(req);
  if (!caller) {
    return fail(req, 401, "Authentification requise.");
  }

  // --- Quelle entrée -------------------------------------------------------
  let storeId: string | undefined;
  if (req.method === "POST") {
    try {
      const body = await req.json();
      storeId = body?.store_id;
    } catch {
      return fail(req, 400, "Corps JSON invalide.");
    }
  } else {
    storeId = new URL(req.url).searchParams.get("store_id") ?? undefined;
  }

  if (typeof storeId !== "string" || !UUID_RE.test(storeId)) {
    return fail(req, 400, "store_id manquant ou mal formé.");
  }

  // --- A-t-il le droit -----------------------------------------------------
  // Sans ce contrôle, n'importe quel compte connecté pourrait rattacher une
  // Page Facebook au magasin d'un autre commerçant, et publier en son nom.
  // Vérifié sous RLS, avec le JWT de l'appelant.
  if (!await isStoreMember(caller, storeId)) {
    log("warn", FN, "Tentative de connexion sur un magasin non membre", {
      storeId,
      userId: caller.userId,
    });
    return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");
  }

  // --- Forger le state -----------------------------------------------------
  // Signature HMAC : empêche la forge.
  // Nonce consommé en base : empêche le rejeu d'un state valide intercepté.
  // Les deux sont nécessaires, aucun ne remplace l'autre.
  const nonce = randomNonce();

  const service = serviceClient();
  const { error: stateError } = await service.rpc("oauth_state_create", {
    p_nonce: nonce,
    p_store_id: storeId,
    p_user_id: caller.userId,
    p_ttl_seconds: STATE_TTL_SECONDS,
  });

  if (stateError) {
    log("error", FN, "Écriture de l'état OAuth impossible", {
      storeId,
      detail: stateError.message,
    });
    return fail(req, 500, "Impossible d'initialiser la connexion.");
  }

  const state = await signState({
    nonce,
    storeId,
    exp: Math.floor(Date.now() / 1000) + STATE_TTL_SECONDS,
  });

  // --- Construire l'URL ----------------------------------------------------
  // `config_id` et non `scope` : Facebook Login for Business passe par une
  // Configuration définie côté Meta, qui porte les permissions et les types de
  // ressources demandés. Les permissions ne sont donc PAS dans cette URL.
  const authorizeUrl = new URL(env.dialogBase);
  authorizeUrl.searchParams.set("client_id", env.metaAppId);
  authorizeUrl.searchParams.set("config_id", env.metaConfigId);
  authorizeUrl.searchParams.set("redirect_uri", env.metaRedirectUri);
  authorizeUrl.searchParams.set("state", state);
  authorizeUrl.searchParams.set("response_type", "code");

  log("info", FN, "Flux OAuth ouvert", { storeId, userId: caller.userId });

  const wantsRedirect = new URL(req.url).searchParams.get("redirect") === "1";
  if (wantsRedirect) {
    return new Response(null, {
      status: 302,
      headers: { Location: authorizeUrl.toString(), "Cache-Control": "no-store" },
    });
  }

  return json(req, {
    authorize_url: authorizeUrl.toString(),
    expires_in: STATE_TTL_SECONDS,
  });
});
