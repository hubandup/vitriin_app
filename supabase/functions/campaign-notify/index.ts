// campaign-notify : email « Nouvelle campagne » aux gérants des magasins, envoyé par Brevo.
//
// JWT requis (verify_jwt = true). Appelée par l'espace centrale juste après l'envoi d'une campagne :
//   POST { promotion_id }
// L'appelant doit être membre de la centrale qui a créé la campagne (vérifié avec SON jeton).
// Seuls les magasins ajoutés à la campagne depuis moins d'une heure et pas encore prévenus reçoivent l'email
// (campaign_notify_claim les réserve) : rappeler la fonction ne renvoie rien.
//   - campagne à valider : « Voir et activer » ;
//   - campagne obligatoire ou validation automatique : « Voir et publier ».

import { createClient } from "jsr:@supabase/supabase-js@2";
import { APP, emailReady, esc, layout, para, sendEmail } from "../_shared/email.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ORIGINS = [APP, "http://localhost:3000", "http://localhost:5173"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return { "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : APP, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" };
}
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });
const day = (d: string) => new Date(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long", timeZone: "Europe/Paris" });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée." }, 405);
  let body: { promotion_id?: unknown };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }
  const promoId = String(body.promotion_id ?? "");
  if (!UUID.test(promoId)) return json(req, { error: "Requête invalide." }, 400);

  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user) return json(req, { error: "Connexion requise." }, 401);
  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });

  const { data: p } = await admin.from("promotions")
    .select("id, title, description, media_url, starts_at, ends_at, is_mandatory, created_by_network_id").eq("id", promoId).maybeSingle();
  if (!p?.created_by_network_id) return json(req, { error: "Campagne introuvable." }, 404);
  const { data: member } = await asUser.rpc("is_network_member", { p_network_id: p.created_by_network_id });
  if (!member) return json(req, { error: "Campagne introuvable." }, 404);
  if (!emailReady()) return json(req, { ok: true, sent: 0, reason: "email non configuré" });

  const { data: net } = await admin.from("networks").select("name").eq("id", p.created_by_network_id).maybeSingle();
  const { data: rows, error } = await admin.rpc("campaign_notify_claim", { p_promotion_id: promoId });
  if (error) { console.error("campaign-notify claim", error.message); return json(req, { error: "Envoi impossible." }, 500); }

  const netName = net?.name ?? "Votre centrale";
  const dates = `Du ${day(p.starts_at)} au ${day(p.ends_at)}`;
  // Seules les images hébergées chez nous s'affichent de façon fiable dans les messageries.
  const img = typeof p.media_url === "string" && p.media_url.startsWith(`${URL_}/storage/v1/object/public/`) ? p.media_url : undefined;
  const text = (p.description ?? "").trim();
  const quote = `<b style="font-size:16px">${esc(p.title)}</b><br><span style="color:#7b766f;font-size:13px">${esc(dates)}</span>${text ? `<br><br>${para(text.length > 400 ? text.slice(0, 400) + "…" : text)}` : ""}`;

  const failed: string[] = [];
  let sent = 0;
  const list = (rows ?? []) as { sp_id: string; status: string; store_name: string; emails: string[] }[];
  // Envoi par lots de 8 en parallèle : une campagne à 300 magasins part en quelques secondes.
  for (let i = 0; i < list.length; i += 8) {
    await Promise.all(list.slice(i, i + 8).map(async (r) => {
      if (!r.emails?.length) return; // magasin sans compte activé : l'invitation s'en charge
      const toValidate = r.status === "pending";
      try {
        await sendEmail({
          to: r.emails, tag: "campagne",
          subject: `${toValidate ? "Nouvelle campagne à activer" : "Nouvelle campagne prête à publier"} · ${p.title}`,
          html: layout({
            pre: `${netName} : ${p.title}. ${dates}.`,
            title: toValidate ? "Une nouvelle campagne vous attend" : "Une nouvelle campagne est prête",
            intro: toValidate
              ? `<b>${esc(netName)}</b> propose une nouvelle campagne pour <b>${esc(r.store_name)}</b>. Activez-la en un clic : elle sera publiée sur votre vitrine et vos réseaux.`
              : `<b>${esc(netName)}</b> a ajouté une campagne à <b>${esc(r.store_name)}</b>. Il ne reste qu'à choisir quand la publier sur vos réseaux.`,
            img, quote,
            cta: [toValidate ? "Voir et activer" : "Voir et publier", `${APP}/magasin/?promo=${r.sp_id}`],
            foot: `Vous recevez cet email car vous gérez ${esc(r.store_name)} sur Vitriin.`,
          }),
        });
        sent++;
      } catch (e) {
        failed.push(r.sp_id);
        console.error("campaign-notify", (e as Error).message);
      }
    }));
  }
  if (failed.length) await admin.rpc("campaign_notify_release", { p_ids: failed });
  return json(req, { ok: true, sent, failed: failed.length });
});
