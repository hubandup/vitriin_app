// meta-health-check — vérifie que les comptes connectés le sont toujours.
//
// Un token de Page n'a pas de date d'expiration : il meurt silencieusement
// quand le commerçant révoque l'accès, perd l'administration de sa Page, ou
// change son mot de passe. Sans cette fonction, on ne l'apprendrait qu'au
// moment où une campagne échoue — c'est-à-dire trop tard, devant le client.
//
// Deux modes d'appel :
//
//   service_role → balayage. Tous les comptes dont la dernière vérification
//                  date. C'est le mode planifié.
//   JWT membre   → un magasin, à la demande. Pour un bouton « vérifier mes
//                  comptes » dans l'app, plus tard.
//
// Planification (Dashboard → Integrations → Cron, ou pg_cron) :
//
//   select net.http_post(
//     url     := 'https://<ref>.supabase.co/functions/v1/meta-health-check',
//     headers := jsonb_build_object(
//                  'Authorization', 'Bearer ' || current_setting('app.service_key'),
//                  'Content-Type',  'application/json'),
//     body    := '{"stale_after_minutes": 360}'::jsonb
//   );
//
// Une fois par heure suffit : on cherche à prévenir, pas à surveiller en
// temps réel.

import { env } from "../_shared/env.ts";
import { fail, json, log, preflight } from "../_shared/http.ts";
import { classify, graph, GraphError, redact } from "../_shared/meta.ts";
import {
  authenticate,
  bearerToken,
  isStoreMember,
  loadAccessToken,
  serviceClient,
} from "../_shared/supabase.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FN = "meta-health-check";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Pour ne pas saturer les quotas Graph sur un gros balayage. */
const BATCH_SIZE = 5;
const MAX_ACCOUNTS = 200;

interface Account {
  id: string;
  store_id: string;
  channel: "facebook" | "instagram";
  external_account_id: string;
  parent_external_id: string | null;
  display_name: string;
  status: string;
}

Deno.serve(async (req) => {
  const cors = preflight(req);
  if (cors) return cors;

  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");

  let body: { store_id?: unknown; stale_after_minutes?: unknown } = {};
  try {
    const raw = await req.text();
    if (raw) body = JSON.parse(raw);
  } catch {
    return fail(req, 400, "Corps JSON invalide.");
  }

  const service = serviceClient();

  // Comparaison exacte avec la clé service_role : c'est elle, et rien d'autre,
  // qui ouvre le mode balayage.
  const isSweep = bearerToken(req) === env.serviceRoleKey;

  let query = service
    .from("social_accounts")
    .select(
      "id, store_id, channel, external_account_id, parent_external_id, display_name, status",
    )
    .in("channel", ["facebook", "instagram"]);

  if (isSweep) {
    // On ne revérifie pas un compte déjà marqué révoqué : il ne redeviendra
    // actif que par une reconnexion, qui remet le statut à jour elle-même.
    query = query.neq("status", "revoked");

    const staleMinutes = Number(body.stale_after_minutes ?? 360);
    if (Number.isFinite(staleMinutes) && staleMinutes > 0) {
      const cutoff = new Date(Date.now() - staleMinutes * 60_000).toISOString();
      query = query.or(`last_checked_at.is.null,last_checked_at.lt.${cutoff}`);
    }
    query = query.limit(MAX_ACCOUNTS);
  } else {
    const caller = await authenticate(req);
    if (!caller) return fail(req, 401, "Authentification requise.");

    const storeId = body.store_id;
    if (typeof storeId !== "string" || !UUID_RE.test(storeId)) {
      return fail(req, 400, "store_id manquant ou mal formé.");
    }
    if (!await isStoreMember(caller, storeId)) {
      return fail(req, 403, "Vous n'êtes pas membre de ce magasin.");
    }
    query = query.eq("store_id", storeId);
  }

  const { data: accounts, error } = await query;

  if (error) {
    log("error", FN, "Lecture des comptes impossible", { detail: error.message });
    return fail(req, 500, "Erreur interne.");
  }

  const results: Array<{
    account_id: string;
    channel: string;
    display_name: string;
    status: string;
    changed: boolean;
    error?: string;
  }> = [];

  // Par petits paquets : un balayage de réseau peut porter sur des centaines
  // de comptes, et Graph applique des quotas par application.
  for (let i = 0; i < (accounts ?? []).length; i += BATCH_SIZE) {
    const batch = (accounts as Account[]).slice(i, i + BATCH_SIZE);
    const checked = await Promise.allSettled(
      batch.map((account) => checkAccount(service, account)),
    );

    checked.forEach((outcome, index) => {
      const account = batch[index];
      if (outcome.status === "fulfilled") {
        results.push(outcome.value);
      } else {
        results.push({
          account_id: account.id,
          channel: account.channel,
          display_name: account.display_name,
          status: account.status,
          changed: false,
          error: redact(outcome.reason?.message ?? outcome.reason),
        });
      }
    });
  }

  const revoked = results.filter((r) => r.status === "revoked").length;

  log("info", FN, "Vérification terminée", {
    mode: isSweep ? "balayage" : "magasin",
    checked: results.length,
    revoked,
  });

  return json(req, { checked: results.length, revoked, results });
});

/**
 * Lit l'objet Meta avec le token du compte.
 *
 * Teste exactement ce qui compte : non pas « le token est-il bien formé »,
 * mais « ce token donne-t-il encore accès à cette Page ». Les deux pannes
 * qu'on cherche — révocation et perte d'administration — tombent ici, la
 * première en code 190, la seconde en 200 ou 10.
 */
async function checkAccount(service: SupabaseClient, account: Account) {
  const base = {
    account_id: account.id,
    channel: account.channel,
    display_name: account.display_name,
  };

  try {
    const token = await loadAccessToken(service, account);
    const data = await graph.get(
      account.external_account_id,
      { fields: account.channel === "instagram" ? "id,username" : "id,name" },
      token,
    );

    // Vérification vivante : on profite de l'appel pour rafraîchir le nom
    // affiché, qu'un commerçant a pu changer entre-temps.
    const freshName = account.channel === "instagram"
      ? (data.username ? String(data.username) : null)
      : (data.name ? String(data.name) : null);

    const patch: Record<string, unknown> = { last_checked_at: new Date().toISOString() };
    if (freshName && freshName !== account.display_name) {
      patch.display_name = freshName;
    }
    if (account.status !== "active") {
      // Un compte en `error` qui répond de nouveau : c'était bien passager.
      patch.status = "active";
      patch.last_error = null;
      patch.last_error_at = null;
    }

    await service.from("social_accounts").update(patch).eq("id", account.id);

    return {
      ...base,
      display_name: freshName ?? account.display_name,
      status: "active",
      changed: account.status !== "active",
    };
  } catch (cause) {
    const detail = cause instanceof GraphError
      ? cause.describe()
      : redact(cause instanceof Error ? cause.message : cause);

    const kind = classify(cause);
    // 'content' n'a pas de sens pour une simple lecture d'objet : si ce n'est
    // ni une révocation ni une panne passagère, on reste prudent et on classe
    // en erreur plutôt que de déconnecter un commerçant à tort.
    const next = kind === "revoked" ? "revoked" : "error";

    await service.rpc("social_account_set_status", {
      p_account_id: account.id,
      p_status: next,
      p_error: detail,
    });

    if (next === "revoked") {
      log("warn", FN, "Compte révoqué détecté", {
        accountId: account.id,
        storeId: account.store_id,
        channel: account.channel,
        detail,
      });
    }

    return {
      ...base,
      status: next,
      changed: account.status !== next,
      error: detail,
    };
  }
}
