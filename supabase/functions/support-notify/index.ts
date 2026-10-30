// support-notify : emails du support, envoyés par Brevo.
//
// JWT requis (verify_jwt = true). Appelée par l'app juste après un message :
//   POST { ticket_id }
//   - message d'un client (magasin, centrale) : email à l'équipe Vitriin (SUPPORT_INBOX), réponse directe au client ;
//   - réponse de l'équipe : email au client, avec un lien vers son espace.
// On n'envoie que les messages de l'appelant pas encore notifiés (notified_at), non internes, de moins d'une
// heure : rappeler la fonction ne renvoie rien, et personne ne peut déclencher un email pour le message d'un autre.
//
// Secrets : BREVO_API_KEY (obligatoire), BREVO_SENDER et SUPPORT_INBOX (facultatifs, hello@vitriin.co par défaut).
// Aucune clé ne sort de la fonction.

import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BREVO = Deno.env.get("BREVO_API_KEY")?.trim() ?? "";
const SENDER = Deno.env.get("BREVO_SENDER")?.trim() || "hello@vitriin.co";
const INBOX = Deno.env.get("SUPPORT_INBOX")?.trim() || "hello@vitriin.co";
const APP = "https://app.vitriin.co";
const ORIGINS = [APP, "http://localhost:3000", "http://localhost:5173"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOGO = `${URL_}/storage/v1/object/public/email-assets/logo-vitriin-blanc.png`;
const TOPICS: Record<string, string> = { social: "Comptes sociaux", publication: "Publication", promo: "Promotion", account: "Compte", billing: "Facturation", other: "Autre" };

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return { "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : APP, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" };
}
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const para = (s: string) => esc(s).replace(/\r?\n/g, "<br>");

// Gabarit commun, identique aux emails d'authentification.
function layout(o: { pre: string; title: string; intro: string; quote: string; meta?: string; cta?: [string, string]; foot: string }) {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.title)}</title></head>
<body style="margin:0;padding:0;background:#f6f3ee;font-family:Helvetica,Arial,sans-serif;color:#2d2d2d">
<span style="display:none;max-height:0;overflow:hidden;opacity:0">${esc(o.pre)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f3ee;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:20px;overflow:hidden">
<tr><td style="background:#e5087e;background-image:linear-gradient(100deg,#e5087e,#951b81);padding:22px 28px"><img src="${LOGO}" width="140" height="30" alt="Vitriin" style="display:block;border:0;outline:none;width:140px;height:auto;color:#ffffff;font-size:22px;font-weight:bold"></td></tr>
<tr><td style="padding:30px 28px 8px">
<h1 style="margin:0 0 14px;font-size:22px;line-height:1.3;color:#2d2d2d">${esc(o.title)}</h1>
<p style="margin:0 0 14px;font-size:15px;line-height:1.6">${o.intro}</p>
<div style="margin:0 0 12px;padding:14px 16px;background:#faf6f0;border-left:4px solid #e5087e;border-radius:8px;font-size:15px;line-height:1.6">${o.quote}</div>
${o.meta ? `<p style="margin:0 0 12px;font-size:13px;line-height:1.55;color:#7b766f">${o.meta}</p>` : ""}
</td></tr>
${o.cta ? `<tr><td style="padding:6px 28px 8px"><a href="${o.cta[1]}" style="display:inline-block;background:#e5087e;color:#ffffff;text-decoration:none;font-weight:bold;font-size:16px;padding:14px 26px;border-radius:12px">${esc(o.cta[0])}</a></td></tr>` : ""}
<tr><td style="padding:16px 28px 28px;font-size:13px;line-height:1.55;color:#7b766f">${o.foot}</td></tr>
</table>
<p style="max-width:520px;margin:16px auto 0;font-size:12px;line-height:1.5;color:#a8a29b;text-align:center">Vitriin, une marque de Hub &amp; Up · 71 chemin du Moulin Carron, 69570 Dardilly</p>
</td></tr></table></body></html>`;
}

async function brevo(to: string, subject: string, html: string, replyTo: string) {
  const r = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": BREVO, "Content-Type": "application/json", accept: "application/json" },
    body: JSON.stringify({ sender: { name: "Vitriin", email: SENDER }, to: [{ email: to }], replyTo: { email: replyTo }, subject, htmlContent: html, tags: ["support"] }),
  });
  if (!r.ok) throw new Error(`Brevo ${r.status} ${(await r.text()).slice(0, 200)}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée." }, 405);
  let body: { ticket_id?: unknown };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }
  const ticketId = String(body.ticket_id ?? "");
  if (!UUID.test(ticketId)) return json(req, { error: "Requête invalide." }, 400);

  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user) return json(req, { error: "Connexion requise." }, 401);
  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });

  const { data: t } = await admin.from("support_tickets")
    .select("id, subject, topic, source, created_by, created_by_email, store:stores(name, city), network:networks(name)")
    .eq("id", ticketId).maybeSingle();
  if (!t) return json(req, { error: "Demande introuvable." }, 404);
  const { data: staff } = await asUser.rpc("is_platform_admin");
  if (!staff && t.created_by !== me.user.id) return json(req, { error: "Demande introuvable." }, 404);
  if (!BREVO) return json(req, { ok: true, sent: 0, reason: "email non configuré" });

  // On réserve les messages avant l'envoi : deux appels simultanés n'envoient pas deux emails.
  const since = new Date(Date.now() - 3600_000).toISOString();
  const { data: msgs } = await admin.from("support_messages").update({ notified_at: new Date().toISOString() })
    .eq("ticket_id", ticketId).eq("author", me.user.id).eq("internal", false).is("notified_at", null).gte("created_at", since)
    .select("id, body, author_kind, created_at").order("created_at");
  if (!msgs?.length) return json(req, { ok: true, sent: 0 });

  const quote = msgs.map((m) => para(m.body)).join("<hr style=\"border:none;border-top:1px solid #eee;margin:12px 0\">");
  const store = t.store as { name?: string; city?: string } | null;
  const net = (t.network as { name?: string } | null)?.name ?? "";
  const who = store?.name ? `${store.name}${store.city ? ` (${store.city})` : ""}${net ? ` · ${net}` : ""}` : net || "Client";
  const subj = t.subject.replace(/[\r\n]+/g, " ");
  try {
    if (msgs[0].author_kind === "client") {
      const { count } = await admin.from("support_messages").select("id", { count: "exact", head: true }).eq("ticket_id", ticketId).eq("internal", false);
      const first = (count ?? 0) <= msgs.length;
      const from = t.created_by_email || me.user.email || "";
      await brevo(INBOX, `${first ? "Nouvelle demande" : "Nouveau message"} · ${who} · ${subj}`, layout({
        pre: `${who} : ${msgs[msgs.length - 1].body.slice(0, 90)}`,
        title: first ? "Nouvelle demande de support" : "Nouveau message du client",
        intro: `<b>${esc(who)}</b>${from ? ` (${esc(from)})` : ""} · ${esc(TOPICS[t.topic] ?? "Autre")}<br><b>${esc(subj)}</b>`,
        quote,
        cta: ["Ouvrir dans le Manager", `${APP}/manager/?ticket=${t.id}`],
        foot: "Répondez depuis le Manager : le client reçoit la réponse par email et dans son espace.",
      }), from || INBOX);
    } else {
      const { data: u } = t.created_by ? await admin.auth.admin.getUserById(t.created_by) : { data: null };
      const to = u?.user?.email || t.created_by_email;
      if (!to) return json(req, { ok: true, sent: 0, reason: "client sans email" });
      const space = t.source === "centrale" ? "centrale" : "magasin";
      await brevo(to, `Réponse à votre demande · ${subj}`, layout({
        pre: msgs[msgs.length - 1].body.slice(0, 100),
        title: "L'équipe Vitriin vous a répondu",
        intro: `Au sujet de votre demande <b>« ${esc(subj)} »</b> :`,
        quote,
        cta: ["Voir la conversation", `${APP}/${space}/?support=${t.id}`],
        foot: "Vous pouvez répondre depuis votre espace Vitriin, rubrique Aide. Une réponse à cet email nous parvient aussi.",
      }), INBOX);
    }
  } catch (e) {
    // Échec d'envoi : on libère les messages pour un prochain essai, sans exposer le détail au navigateur.
    await admin.from("support_messages").update({ notified_at: null }).in("id", msgs.map((m) => m.id));
    console.error("support-notify", (e as Error).message);
    return json(req, { ok: false, error: "Envoi de l'email impossible." }, 502);
  }
  return json(req, { ok: true, sent: msgs.length });
});
