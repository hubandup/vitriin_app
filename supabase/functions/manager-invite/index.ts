// manager-invite — l'équipe Vitriin ajoute un utilisateur à une centrale ou à un magasin (Manager).
//
// JWT requis (verify_jwt = true). L'appelant doit être dans platform_admins :
// vérifié avec SON jeton (is_platform_admin) avant toute action en service_role.
//
//   POST { network_id, email, role: "owner"|"admin"|"member" }          -> équipe de la centrale
//   POST { network_id, store_id, email }                                 -> gérant d'un magasin de cette centrale
//   - le compte existe : il est rattaché (son rôle centrale est mis à jour) ;
//   - sinon : Supabase envoie l'email d'invitation, le compte est créé et rattaché.
//   POST { action: "change_email", network_id, store_id, user_id, email }
//                                                                        -> nouvel email du gérant d'un magasin de cette
//      centrale : l'email du compte est remplacé, le magasin mis à jour, et un lien pour choisir un mot de passe part
//      à la nouvelle adresse.
//
// La clé service_role reste dans la fonction : elle ne sort jamais vers le navigateur.

import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ORIGINS = ["https://app.vitriin.co", "http://localhost:3000", "http://localhost:5173"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (req: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée." }, 405);

  let body: { action?: unknown; network_id?: unknown; store_id?: unknown; user_id?: unknown; email?: unknown; role?: unknown };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }
  const networkId = String(body.network_id ?? "");
  const storeId = body.store_id ? String(body.store_id) : null;
  const email = String(body.email ?? "").trim().toLowerCase();
  const role = ["owner", "admin", "member"].includes(String(body.role)) ? String(body.role) : "member";
  if (!UUID.test(networkId) || (storeId && !UUID.test(storeId))) return json(req, { error: "Requête invalide." }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 200) return json(req, { error: "Email invalide." }, 400);

  // 1. Équipe Vitriin uniquement, vérifié avec le jeton de l'appelant.
  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user) return json(req, { error: "Connexion requise." }, 401);
  const { data: staff, error: e0 } = await asUser.rpc("is_platform_admin");
  if (e0 || !staff) return json(req, { error: "Accès réservé à l'équipe Vitriin." }, 403);

  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  if (storeId) {
    const { data: st } = await admin.from("stores").select("id").eq("id", storeId).eq("network_id", networkId).maybeSingle();
    if (!st) return json(req, { error: "Ce magasin n'appartient pas à cette centrale." }, 400);
  } else {
    const { data: n } = await admin.from("networks").select("id").eq("id", networkId).maybeSingle();
    if (!n) return json(req, { error: "Centrale introuvable." }, 404);
  }

  // Changement d'email d'un gérant de magasin.
  if (body.action === "change_email") {
    const userId = String(body.user_id ?? "");
    if (!storeId || !UUID.test(userId)) return json(req, { error: "Requête invalide." }, 400);
    const { data: link } = await admin.from("store_members").select("user_id").eq("store_id", storeId).eq("user_id", userId).maybeSingle();
    if (!link) return json(req, { error: "Ce compte n'est pas gérant de ce magasin." }, 400);
    const { data: staffTarget } = await admin.from("platform_admins").select("user_id").eq("user_id", userId).maybeSingle();
    if (staffTarget) return json(req, { error: "Un compte de l'équipe Vitriin ne se modifie pas d'ici." }, 400);
    const { data: other } = await admin.rpc("user_id_by_email", { p_email: email });
    if (other && other !== userId) return json(req, { error: "Cette adresse est déjà utilisée par un autre compte." }, 409);
    const { error: e3 } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true });
    if (e3) return json(req, { error: "Modification impossible : " + e3.message }, 502);
    await admin.from("stores").update({ contact_email: email }).eq("id", storeId);
    // Lien pour choisir un mot de passe, envoyé à la nouvelle adresse.
    const origin = req.headers.get("Origin");
    const base = origin && ORIGINS.includes(origin) ? origin : ORIGINS[0];
    const anon = createClient(URL_, ANON, { auth: { persistSession: false } });
    const { error: e4 } = await anon.auth.resetPasswordForEmail(email, { redirectTo: `${base}/magasin/?bienvenue=1` });
    return json(req, { ok: true, changed: true, mailed: !e4 });
  }

  // 2. Compte existant, sinon invitation par email.
  let { data: userId } = await admin.rpc("user_id_by_email", { p_email: email });
  let invited = false;
  if (!userId) {
    const origin = req.headers.get("Origin");
    const base = origin && ORIGINS.includes(origin) ? origin : ORIGINS[0];
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo: `${base}/${storeId ? "magasin" : "centrale"}/?bienvenue=1` });
    if (error || !data?.user) {
      const rate = /rate|limit|too many/i.test(error?.message ?? "");
      return json(req, { error: rate ? "Limite d'envoi d'emails atteinte, réessayez plus tard." : "Invitation impossible : " + (error?.message ?? "erreur inconnue") }, 502);
    }
    userId = data.user.id; invited = true;
  }

  // 3. Rattachement.
  const { error: e2 } = storeId
    ? await admin.from("store_members").upsert({ store_id: storeId, user_id: userId, role: "owner" }, { onConflict: "store_id,user_id", ignoreDuplicates: true })
    : await admin.from("network_members").upsert({ network_id: networkId, user_id: userId, role }, { onConflict: "network_id,user_id" });
  if (e2) return json(req, { error: "Rattachement impossible : " + e2.message }, 500);
  if (storeId && invited) await admin.from("stores").update({ invited_at: new Date().toISOString() }).eq("id", storeId);

  return json(req, { ok: true, invited });
});
