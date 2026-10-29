// network-invite — ajoute un utilisateur à l'équipe d'une centrale.
//
// JWT requis (verify_jwt = true). L'appelant doit être admin ou propriétaire
// du réseau : vérifié ici avec SON jeton, avant toute action en service_role.
//
//   POST { network_id, email, role: "admin" | "member" }
//   - le compte existe : il est rattaché au réseau ;
//   - sinon : Supabase lui envoie un email d'invitation, puis il est rattaché.
//
// La clé service_role reste dans la fonction (variable injectée par
// Supabase) : elle ne sort jamais vers le navigateur.

import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ORIGINS = ["https://app.vitriin.co", "http://localhost:3000", "http://localhost:5173"];

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

  let body: { network_id?: string; email?: string; role?: string };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }

  const networkId = String(body.network_id ?? "");
  const email = String(body.email ?? "").trim().toLowerCase();
  const role = body.role === "admin" ? "admin" : "member";
  if (!/^[0-9a-f-]{36}$/.test(networkId)) return json(req, { error: "Réseau invalide." }, 400);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 200) return json(req, { error: "Email invalide." }, 400);

  // 1. Qui appelle ? Vérification avec le jeton de l'appelant (RLS appliquée).
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: auth } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user) return json(req, { error: "Connexion requise." }, 401);
  const { data: isAdmin, error: e0 } = await asUser.rpc("is_network_admin", { p_network_id: networkId });
  if (e0 || !isAdmin) return json(req, { error: "Seuls les administrateurs de la centrale peuvent ajouter des utilisateurs." }, 403);

  // 2. Le compte existe-t-il ? Sinon, invitation par email.
  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  let { data: userId } = await admin.rpc("user_id_by_email", { p_email: email });
  let invited = false;
  if (!userId) {
    const origin = req.headers.get("Origin");
    const redirectTo = `${origin && ORIGINS.includes(origin) ? origin : ORIGINS[0]}/centrale/?bienvenue=1`;
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
    if (error || !data?.user) return json(req, { error: "Invitation impossible : " + (error?.message ?? "erreur inconnue") }, 502);
    userId = data.user.id; invited = true;
  }

  // 3. Rattachement (sans toucher au rôle d'un membre existant).
  const { error: e2 } = await admin.from("network_members")
    .upsert({ network_id: networkId, user_id: userId, role }, { onConflict: "network_id,user_id", ignoreDuplicates: true });
  if (e2) return json(req, { error: "Rattachement impossible : " + e2.message }, 500);

  return json(req, { ok: true, invited });
});
