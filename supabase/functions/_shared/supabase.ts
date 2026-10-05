// Clients Supabase et accès au chiffré.
//
// Deux clients, deux rôles, jamais confondus :
//
//   serviceClient() — contourne la RLS. Pour écrire social_accounts et
//                     publications, que le schéma réserve volontairement aux
//                     Edge Functions. Ne doit JAMAIS servir à décider si
//                     l'appelant a le droit de faire quelque chose.
//
//   userClient(jwt) — porte le JWT de l'appelant, donc soumis à la RLS. C'est
//                     lui qui répond à « cette personne est-elle membre de ce
//                     magasin ». On délègue l'autorisation aux policies déjà
//                     écrites plutôt que de la réimplémenter ici.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { env } from "./env.ts";
import { accountAad, decryptToken, fromPgHex } from "./crypto.ts";

export function serviceClient(): SupabaseClient {
  return createClient(env.supabaseUrl, env.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function userClient(jwt: string): SupabaseClient {
  return createClient(env.supabaseUrl, env.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}

/** Extrait le JWT d'un en-tête `Authorization: Bearer …`. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

export interface Caller {
  userId: string;
  jwt: string;
}

/**
 * Identifie l'appelant. Rend `null` si le JWT est absent, invalide ou expiré —
 * y compris si c'est la clé anon, qui ne porte aucun utilisateur.
 */
export async function authenticate(req: Request): Promise<Caller | null> {
  const jwt = bearerToken(req);
  if (!jwt) return null;

  // Le JWT est passé explicitement à getUser() plutôt que déduit d'une session :
  // il n'y a pas de session ici (persistSession: false), et compter sur
  // l'en-tête global pour que getUser() le retrouve dépend de la version de
  // supabase-js.
  const { data, error } = await userClient(jwt).auth.getUser(jwt);
  if (error || !data?.user) return null;

  return { userId: data.user.id, jwt };
}

/**
 * Vérifie l'appartenance au magasin SOUS RLS, avec le JWT de l'appelant.
 *
 * Délibérément pas en service_role : la policy store_members_select de la
 * migration initiale sait déjà qui a le droit de voir quoi. La contourner
 * ici pour refaire le test à la main, c'est se créer une seconde source de
 * vérité qui dérivera de la première.
 */
export async function isStoreMember(
  caller: Caller,
  storeId: string,
): Promise<boolean> {
  const { data, error } = await userClient(caller.jwt)
    .from("store_members")
    .select("store_id")
    .eq("store_id", storeId)
    .eq("user_id", caller.userId)
    .maybeSingle();

  return !error && data !== null;
}

/**
 * Récupère et déchiffre le token d'un compte.
 *
 * Le seul endroit du système où un token existe en clair, et uniquement en
 * mémoire du worker. La valeur rendue ne doit jamais être journalisée, ni
 * sérialisée dans une réponse, ni placée dans une URL.
 */
export async function loadAccessToken(
  service: SupabaseClient,
  account: { id: string; store_id: string; channel: string; external_account_id: string },
): Promise<string> {
  const { data, error } = await service.rpc("social_account_token_get", {
    p_account_id: account.id,
  });

  if (error) {
    throw new Error(`Lecture du token impossible : ${error.message}`);
  }
  if (!data) {
    // La ligne publique existe mais pas son secret. social_account_upsert écrit
    // les deux dans la même transaction, donc ce cas ne devrait pas exister —
    // sauf suppression manuelle en base.
    throw new Error("Aucun token stocké pour ce compte : reconnexion requise.");
  }

  return await decryptToken(
    fromPgHex(data as string),
    accountAad(account.store_id, account.channel, account.external_account_id),
  );
}
