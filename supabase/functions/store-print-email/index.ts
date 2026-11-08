// store-print-email : envoie au commerçant, par email, le QR code ou l'affiche de sa vitrine (MOD-080).
//
// JWT requis (verify_jwt = true). Appelée depuis l'onglet Magasin :
//   POST { store_id, kind: "qr" | "poster", file }   file = PNG (qr) ou PDF (poster) en base64, 6 Mo max.
// Sécurité : l'appelant doit être membre du magasin (RLS, via is_store_member) ; l'email part UNIQUEMENT à
// l'adresse de son propre compte, jamais à une adresse fournie : la fonction ne peut pas servir de relais.
// Le fichier est vérifié (en-tête PNG ou PDF) et n'est pas conservé.
//
// Secrets : BREVO_API_KEY et BREVO_SENDER (voir _shared/email.ts). Aucune clé ne sort de la fonction.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { APP, emailReady, esc, layout, sendEmail } from "../_shared/email.ts";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const ORIGINS = [APP, "http://localhost:3000", "http://localhost:5173"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_B64 = 8_000_000; // ~6 Mo de fichier

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return { "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : APP, "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin" };
}
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée." }, 405);
  let body: { store_id?: unknown; kind?: unknown; file?: unknown };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }
  const storeId = String(body.store_id ?? ""), kind = String(body.kind ?? ""), file = String(body.file ?? "");
  if (!UUID.test(storeId) || !["qr", "poster"].includes(kind) || !file || file.length > MAX_B64 || !/^[A-Za-z0-9+/=]+$/.test(file)) {
    return json(req, { error: "Requête invalide." }, 400);
  }
  // En-tête du fichier : PNG pour le QR seul, PDF pour l'affiche.
  const head = atob(file.slice(0, 12));
  if (kind === "qr" ? !head.startsWith("\x89PNG") : !head.startsWith("%PDF")) return json(req, { error: "Fichier invalide." }, 400);

  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user?.email) return json(req, { error: "Connexion requise." }, 401);
  const { data: member } = await asUser.rpc("is_store_member", { p_store_id: storeId });
  if (member !== true) return json(req, { error: "Magasin introuvable." }, 404);
  const { data: st } = await asUser.from("stores").select("name, slug").eq("id", storeId).maybeSingle();
  if (!st?.slug) return json(req, { error: "Votre vitrine n'a pas encore d'adresse." }, 400);
  if (!emailReady()) return json(req, { error: "L'envoi d'emails n'est pas configuré." }, 503);

  const link = `${APP}/v/m/${encodeURIComponent(st.slug)}`;
  const poster = kind === "poster";
  try {
    await sendEmail({
      to: [me.user.email], tag: "store-print",
      subject: poster ? `Votre affiche Vitriin · ${st.name}` : `Le QR code de votre vitrine · ${st.name}`,
      attachment: [{ name: poster ? `affiche-vitriin-${st.slug}.pdf` : `qr-vitrine-${st.slug}.png`, content: file }],
      html: layout({
        pre: poster ? "Votre affiche est en pièce jointe, prête à imprimer." : "Le QR code de votre vitrine est en pièce jointe.",
        title: poster ? "Votre affiche est prête" : "Le QR code de votre vitrine",
        intro: poster
          ? `L'affiche de <b>${esc(st.name)}</b> est en pièce jointe, au format A4 (elle s'imprime aussi en A5). Ouvrez-la sur un ordinateur et imprimez-la, ou confiez-la à votre imprimeur.`
          : `Le QR code de <b>${esc(st.name)}</b> est en pièce jointe. Placez-le sur vos supports (vitrine, comptoir, flyers, cartes) : il mène à toutes vos promos en cours.`,
        cta: ["Voir ma vitrine", link],
        foot: `Le QR code ne change jamais : il mène toujours à ${esc(link.replace(/^https:\/\//, ""))}, même quand vos promos changent.`,
      }),
    });
  } catch (e) {
    console.error("store-print-email", (e as Error).message);
    return json(req, { error: "L'email n'a pas pu partir. Réessayez dans un instant." }, 502);
  }
  return json(req, { ok: true, to: me.user.email });
});
