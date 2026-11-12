// publish-scheduled — publie les publications programmées arrivées à échéance
// (MOD-082).
//
// Appelée chaque minute par pg_cron (job « vitriin-publish-scheduled »), jamais
// par un navigateur. Pas de JWT : l'appel porte l'en-tête x-scheduler-secret,
// comparé en base au secret Vault « scheduler_cron_secret » (RPC
// scheduler_check_secret, réservée au service).
//
// Interrupteur : tant que le secret SCHEDULER_ENABLED ne vaut pas "true", la
// fonction compte les publications dues et ne publie RIEN. Il reste coupé
// jusqu'à la validation de l'App Review Meta.
//
// L'accord du magasin a été donné en amont, par schedule_publication (membre du
// magasin vérifié en base). Ici on reprend la ligne programmée exactement comme
// meta-publish reprend une ligne en échec : UPDATE conditionnel sur le statut,
// donc deux exécutions qui se chevauchent ne publient jamais deux fois.

import { fail, json, log } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import {
  loadActivation,
  publishActivation,
  PUBLISH_CHANNELS,
  PublishRefused,
  type PublishChannel,
} from "../_shared/publish.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FN = "publish-scheduled";

/** Activations traitées par exécution : la fonction doit finir avant la suivante. */
const BATCH = 8;

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(req, 405, "Méthode non autorisée.");

  const service = serviceClient();

  const secret = req.headers.get("x-scheduler-secret") ?? "";
  if (secret.length < 32) return fail(req, 401, "Non autorisé.");
  const { data: ok, error: secretError } = await service.rpc("scheduler_check_secret", { p_secret: secret });
  if (secretError || ok !== true) return fail(req, 401, "Non autorisé.");

  // Une publication restée « en cours » plus de 15 min passe en échec,
  // reprenable par le magasin.
  const { data: released } = await service.rpc("publications_release_stuck");

  const now = new Date().toISOString();
  const { data: due, error: dueError } = await service
    .from("publications")
    .select("store_promotion_id, channel, scheduled_at")
    .eq("status", "scheduled")
    .lte("scheduled_at", now)
    .order("scheduled_at")
    .limit(BATCH * PUBLISH_CHANNELS.length);

  if (dueError) {
    log("error", FN, "Lecture des publications dues impossible", { detail: dueError.message });
    return fail(req, 500, "Erreur interne.");
  }

  // Une activation, ses canaux dus.
  const byActivation = new Map<string, PublishChannel[]>();
  for (const row of due ?? []) {
    if (!PUBLISH_CHANNELS.includes(row.channel as PublishChannel)) continue;
    const list = byActivation.get(row.store_promotion_id) ?? [];
    list.push(row.channel as PublishChannel);
    byActivation.set(row.store_promotion_id, list);
  }

  if (Deno.env.get("SCHEDULER_ENABLED") !== "true") {
    if (byActivation.size) {
      log("info", FN, "Interrupteur coupé : rien n'est publié", { due: byActivation.size });
    }
    return json(req, { enabled: false, due: byActivation.size, released: released ?? 0 });
  }

  const report: { store_promotion_id: string; published: number; failed: number; refused?: string }[] = [];

  for (const [storePromotionId, channels] of [...byActivation].slice(0, BATCH)) {
    try {
      const activation = await loadActivation(service, storePromotionId);
      if (!activation) continue; // supprimée entre-temps : ses publications aussi (cascade)

      const ended = await promotionEnded(service, activation.promotion_id);
      if (ended) throw new PublishRefused(409, "La promotion s'est terminée avant la date programmée.");

      const r = await publishActivation(service, activation, channels, FN);
      report.push({ store_promotion_id: storePromotionId, published: r.published, failed: r.failed });
    } catch (cause) {
      const message = cause instanceof PublishRefused
        ? cause.message
        : "Publication programmée impossible : réessayez depuis l'app.";
      if (!(cause instanceof PublishRefused)) {
        log("error", FN, "Publication programmée en panne", {
          storePromotionId,
          detail: cause instanceof Error ? cause.message : String(cause),
        });
      }
      // La ligne ne doit pas rester programmée : elle serait retentée chaque minute.
      await service
        .from("publications")
        .update({ status: "failed", error_message: message })
        .eq("store_promotion_id", storePromotionId)
        .eq("status", "scheduled")
        .in("channel", channels);
      report.push({ store_promotion_id: storePromotionId, published: 0, failed: channels.length, refused: message });
    }
  }

  log("info", FN, "Passage du planificateur", {
    activations: report.length,
    published: report.reduce((n, r) => n + r.published, 0),
    failed: report.reduce((n, r) => n + r.failed, 0),
    remaining: Math.max(0, byActivation.size - BATCH),
  });

  return json(req, { enabled: true, released: released ?? 0, report });
});

async function promotionEnded(service: SupabaseClient, promotionId: string): Promise<boolean> {
  const { data } = await service.from("promotions").select("ends_at").eq("id", promotionId).maybeSingle();
  return !data || new Date(data.ends_at as string).getTime() <= Date.now();
}
