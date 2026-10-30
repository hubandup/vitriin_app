// network-stores-invite — invite les gérants des magasins importés par une centrale.
//
// JWT requis (verify_jwt = true). L'appelant doit être admin du réseau (ou de l'équipe Vitriin) :
// vérifié avec SON jeton avant toute action en service_role.
//
//   POST { network_id, store_ids: uuid[] }  (200 magasins max par appel)
//   Pour chaque magasin du réseau qui a un email de gérant et aucun membre :
//   - le compte existe déjà : il est rattaché au magasin (rien à envoyer) ;
//   - sinon : Supabase envoie l'email d'invitation, le compte est créé et
//     rattaché au magasin. Le gérant choisit son mot de passe en arrivant.
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

type Result = { id: string; name: string; email: string | null; status: "invited" | "linked" | "skipped" | "failed"; reason?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "Méthode non autorisée." }, 405);

  let body: { network_id?: unknown; store_ids?: unknown };
  try { body = await req.json(); } catch { return json(req, { error: "Requête invalide." }, 400); }

  const networkId = String(body.network_id ?? "");
  if (!UUID.test(networkId)) return json(req, { error: "Réseau invalide." }, 400);
  const ids = Array.isArray(body.store_ids) ? [...new Set(body.store_ids.map(String))].filter((x) => UUID.test(x)) : [];
  if (!ids.length) return json(req, { error: "Aucun magasin à inviter." }, 400);
  if (ids.length > 200) return json(req, { error: "200 magasins maximum par envoi." }, 400);

  // 1. Qui appelle ? Vérification avec le jeton de l'appelant (RLS appliquée).
  const auth = req.headers.get("Authorization") ?? "";
  const asUser = createClient(URL_, ANON, { global: { headers: { Authorization: auth } } });
  const { data: me } = await asUser.auth.getUser();
  if (!me?.user) return json(req, { error: "Connexion requise." }, 401);
  // Admin de la centrale, ou équipe Vitriin (Manager) : vérifié en base avec le jeton de l'appelant.
  const { data: isAdmin, error: e0 } = await asUser.rpc("is_network_admin", { p_network_id: networkId });
  const { data: isStaff } = isAdmin ? { data: false } : await asUser.rpc("is_platform_admin");
  if (e0 || !(isAdmin || isStaff)) return json(req, { error: "Seuls les administrateurs de la centrale peuvent inviter des magasins." }, 403);

  // 2. Les magasins, strictement ceux de CE réseau.
  const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });
  const { data: stores, error: e1 } = await admin.from("stores")
    .select("id, name, contact_email, store_members(user_id)")
    .eq("network_id", networkId).in("id", ids);
  if (e1) return json(req, { error: "Lecture des magasins impossible." }, 500);

  const origin = req.headers.get("Origin");
  const redirectTo = `${origin && ORIGINS.includes(origin) ? origin : ORIGINS[0]}/magasin/?bienvenue=1`;
  const results: Result[] = [];

  for (const s of stores ?? []) {
    const email = (s.contact_email ?? "").trim().toLowerCase();
    const base = { id: s.id, name: s.name, email: email || null };
    if (!email) { results.push({ ...base, status: "skipped", reason: "Pas d'email de gérant" }); continue; }
    if ((s.store_members ?? []).length) { results.push({ ...base, status: "skipped", reason: "Déjà activé" }); continue; }

    let { data: userId } = await admin.rpc("user_id_by_email", { p_email: email });
    let status: Result["status"] = "linked";
    if (!userId) {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
      if (error || !data?.user) {
        const rate = /rate|limit|too many/i.test(error?.message ?? "");
        results.push({ ...base, status: "failed", reason: rate ? "Limite d'envoi atteinte, réessayez plus tard" : "Envoi impossible" });
        continue;
      }
      userId = data.user.id; status = "invited";
    }
    const { error: e2 } = await admin.from("store_members")
      .upsert({ store_id: s.id, user_id: userId, role: "owner" }, { onConflict: "store_id,user_id", ignoreDuplicates: true });
    if (e2) { results.push({ ...base, status: "failed", reason: "Rattachement impossible" }); continue; }
    await admin.from("stores").update({ invited_at: new Date().toISOString() }).eq("id", s.id);
    results.push({ ...base, status });
  }

  return json(req, { results });
});
