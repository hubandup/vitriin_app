// Emails transactionnels Vitriin envoyés par Brevo : gabarit commun et envoi.
// Secrets : BREVO_API_KEY (sans elle, rien ne part), BREVO_SENDER (hello@vitriin.co par défaut).

const BREVO = Deno.env.get("BREVO_API_KEY")?.trim() ?? "";
const SENDER = Deno.env.get("BREVO_SENDER")?.trim() || "hello@vitriin.co";
const LOGO = `${Deno.env.get("SUPABASE_URL")}/storage/v1/object/public/email-assets/logo-vitriin-blanc.png`;

export const APP = "https://app.vitriin.co";
export const emailReady = () => !!BREVO;
export const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
export const para = (s: string) => esc(s).replace(/\r?\n/g, "<br>");

/** Gabarit identique aux emails d'authentification. `intro`, `quote` et `foot` sont du HTML déjà échappé. */
export function layout(o: { pre: string; title: string; intro: string; quote?: string; img?: string; cta?: [string, string]; foot: string }) {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(o.title)}</title></head>
<body style="margin:0;padding:0;background:#f6f3ee;font-family:Helvetica,Arial,sans-serif;color:#2d2d2d">
<span style="display:none;max-height:0;overflow:hidden;opacity:0">${esc(o.pre)}</span>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f3ee;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:20px;overflow:hidden">
<tr><td style="background:#e5087e;background-image:linear-gradient(100deg,#e5087e,#951b81);padding:22px 28px"><img src="${LOGO}" width="140" height="30" alt="Vitriin" style="display:block;border:0;outline:none;width:140px;height:auto;color:#ffffff;font-size:22px;font-weight:bold"></td></tr>
<tr><td style="padding:30px 28px 8px">
<h1 style="margin:0 0 14px;font-size:22px;line-height:1.3;color:#2d2d2d">${esc(o.title)}</h1>
<p style="margin:0 0 14px;font-size:15px;line-height:1.6">${o.intro}</p>
${o.img ? `<img src="${esc(o.img)}" width="464" alt="" style="display:block;width:100%;max-width:464px;height:auto;border:0;border-radius:14px;margin:0 0 14px">` : ""}
${o.quote ? `<div style="margin:0 0 12px;padding:14px 16px;background:#faf6f0;border-left:4px solid #e5087e;border-radius:8px;font-size:15px;line-height:1.6">${o.quote}</div>` : ""}
</td></tr>
${o.cta ? `<tr><td style="padding:6px 28px 8px"><a href="${esc(o.cta[1])}" style="display:inline-block;background:#e5087e;color:#ffffff;text-decoration:none;font-weight:bold;font-size:16px;padding:14px 26px;border-radius:12px">${esc(o.cta[0])}</a></td></tr>` : ""}
<tr><td style="padding:16px 28px 28px;font-size:13px;line-height:1.55;color:#7b766f">${o.foot}</td></tr>
</table>
<p style="max-width:520px;margin:16px auto 0;font-size:12px;line-height:1.5;color:#a8a29b;text-align:center">Vitriin, une marque de Hub &amp; Up · 71 chemin du Moulin Carron, 69570 Dardilly</p>
</td></tr></table></body></html>`;
}

export async function sendEmail(o: { to: string[]; subject: string; html: string; replyTo?: string; tag: string }) {
  const r = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": BREVO, "Content-Type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      sender: { name: "Vitriin", email: SENDER }, to: o.to.map((email) => ({ email })),
      ...(o.replyTo ? { replyTo: { email: o.replyTo } } : {}),
      subject: o.subject.replace(/[\r\n]+/g, " "), htmlContent: o.html, tags: [o.tag],
    }),
  });
  if (!r.ok) throw new Error(`Brevo ${r.status} ${(await r.text()).slice(0, 200)}`);
}
