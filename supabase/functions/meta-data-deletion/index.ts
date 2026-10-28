// meta-data-deletion — reçoit les demandes de suppression et de
// désautorisation envoyées par Meta.
//
// PUBLIQUE (verify_jwt = false), et c'est obligatoire : c'est Meta qui appelle,
// serveur à serveur, sans JWT Supabase. La sécurité repose sur la signature du
// `signed_request`, un HMAC-SHA256 calculé avec l'App Secret : sans le secret,
// impossible de forger une demande qui efface les comptes d'un tiers.
//
// Trois usages :
//
//   POST                        « Data Deletion Request URL » du tableau de bord
//                               Meta. Efface, puis rend { url, confirmation_code }
//                               comme Meta l'exige.
//
//   POST ?event=deauthorize     « Deauthorize Callback URL ». La personne a
//                               retiré Vitriin de son compte Facebook : ses
//                               tokens sont déjà morts côté Meta, on les efface
//                               aussi côté Vitriin.
//
//   GET  ?code=…                L'URL de suivi transmise à la personne. Rend le
//                               statut en texte simple.
//
// Ce qui est effacé : les comptes Facebook et Instagram connectés par cette
// personne, et leurs tokens chiffrés. Les promotions et publications restent :
// ce sont les données du magasin, pas des données obtenues de Facebook.

import { env } from "../_shared/env.ts";
import { log } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

const FN = "meta-data-deletion";

/** Une demande signée trop ancienne est refusée (rejeu). */
const MAX_AGE_SECONDS = 24 * 3600;

Deno.serve(async (req) => {
  if (req.method === "GET") return statusPage(req);
  if (req.method !== "POST") {
    return text("Méthode non autorisée.", 405);
  }

  const url = new URL(req.url);
  const source = url.searchParams.get("event") === "deauthorize"
    ? "deauthorize"
    : "deletion";

  // --- Le signed_request ---------------------------------------------------
  // Meta l'envoie en formulaire urlencodé. On accepte aussi le JSON, utile
  // pour les tests manuels.
  let signedRequest: string | null = null;
  try {
    const type = req.headers.get("Content-Type") ?? "";
    if (type.includes("application/json")) {
      signedRequest = (await req.json())?.signed_request ?? null;
    } else {
      signedRequest = (await req.formData()).get("signed_request")?.toString() ?? null;
    }
  } catch {
    signedRequest = null;
  }

  if (!signedRequest) {
    return jsonResponse({ error: "signed_request manquant." }, 400);
  }

  const payload = await verifySignedRequest(signedRequest);
  if (!payload) {
    log("warn", FN, "signed_request refusé (signature invalide)", { source });
    return jsonResponse({ error: "Signature invalide." }, 400);
  }

  const metaUserId = typeof payload.user_id === "string"
    ? payload.user_id
    : payload.user_id !== undefined
    ? String(payload.user_id)
    : "";

  if (!/^\d{1,32}$/.test(metaUserId)) {
    return jsonResponse({ error: "user_id manquant ou mal formé." }, 400);
  }

  const issuedAt = Number(payload.issued_at ?? 0);
  if (issuedAt && Date.now() / 1000 - issuedAt > MAX_AGE_SECONDS) {
    return jsonResponse({ error: "Demande expirée." }, 400);
  }

  // --- L'effacement --------------------------------------------------------
  const confirmationCode = newConfirmationCode();
  const { data: deleted, error } = await serviceClient().rpc(
    "data_deletion_execute",
    {
      p_confirmation_code: confirmationCode,
      p_meta_user_id: metaUserId,
      p_source: source,
    },
  );

  if (error) {
    log("error", FN, "Effacement impossible", { source, detail: error.message });
    // 500 : Meta réessaiera. Mieux vaut un nouvel essai qu'une demande perdue.
    return jsonResponse({ error: "Erreur interne." }, 500);
  }

  log("info", FN, "Demande traitée", {
    source,
    confirmationCode,
    accountsDeleted: deleted,
  });

  if (source === "deauthorize") {
    // Meta n'attend aucun contenu particulier pour une désautorisation.
    return jsonResponse({ ok: true }, 200);
  }

  const statusUrl = new URL(`${env.supabaseUrl}/functions/v1/${FN}`);
  statusUrl.searchParams.set("code", confirmationCode);

  return jsonResponse({
    url: statusUrl.toString(),
    confirmation_code: confirmationCode,
  }, 200);
});

// -----------------------------------------------------------------------------
// URL de suivi
// -----------------------------------------------------------------------------
// En texte simple : Supabase sert de toute façon les réponses de ses fonctions
// en text/plain sur *.supabase.co, une page HTML s'afficherait en code brut.

async function statusPage(req: Request): Promise<Response> {
  const code = new URL(req.url).searchParams.get("code") ?? "";
  if (!/^[A-Z0-9]{12,40}$/.test(code)) {
    return text(
      "Vitriin · Suppression des données\n\n" +
        "Code de confirmation manquant ou invalide.\n" +
        "Missing or invalid confirmation code.\n\n" +
        "Contact : hello@vitriin.co",
      400,
    );
  }

  const { data, error } = await serviceClient().rpc("data_deletion_status", {
    p_confirmation_code: code,
  });

  if (error) {
    log("error", FN, "Lecture du statut impossible", { detail: error.message });
    return text("Erreur interne. Réessayez plus tard.", 500);
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return text(
      "Vitriin · Suppression des données\n\n" +
        `Aucune demande trouvée pour le code ${code}.\n` +
        `No request found for code ${code}.\n\n` +
        "Contact : hello@vitriin.co",
      404,
    );
  }

  const date = (iso: string) =>
    new Date(iso).toLocaleString("fr-FR", { timeZone: "Europe/Paris" });

  return text(
    "Vitriin · Suppression des données / Data deletion\n\n" +
      `Code de confirmation : ${code}\n` +
      `Demande reçue le : ${date(row.requested_at)}\n` +
      (row.completed_at
        ? `Statut : TERMINÉE le ${date(row.completed_at)}\n` +
          "Les comptes Facebook et Instagram connectés à Vitriin et leurs accès ont été supprimés.\n\n" +
          "Status: COMPLETED. Connected Facebook and Instagram accounts and their access tokens have been deleted.\n"
        : "Statut : EN COURS / Status: IN PROGRESS\n") +
      "\nQuestions : hello@vitriin.co · https://www.vitriin.fr/suppression-donnees",
    200,
  );
}

// -----------------------------------------------------------------------------
// signed_request
// -----------------------------------------------------------------------------
// Format Meta : « signature.payload », chacun en base64url. La signature est un
// HMAC-SHA256 du payload (la chaîne encodée, telle quelle) avec l'App Secret.

async function verifySignedRequest(
  signedRequest: string,
): Promise<Record<string, unknown> | null> {
  const dot = signedRequest.indexOf(".");
  if (dot <= 0) return null;

  const encodedSig = signedRequest.slice(0, dot);
  const encodedPayload = signedRequest.slice(dot + 1);

  let signature: Uint8Array;
  let payload: Record<string, unknown>;
  try {
    signature = base64UrlDecode(encodedSig);
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(encodedPayload)));
  } catch {
    return null;
  }

  if (String(payload.algorithm ?? "").toUpperCase() !== "HMAC-SHA256") {
    return null;
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.metaAppSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(encodedPayload)),
  );

  return timingSafeEqual(signature, expected) ? payload : null;
}

function base64UrlDecode(input: string): Uint8Array {
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/** Comparaison en temps constant : ne pas révéler où la signature diverge. */
function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Code lisible, sans caractères ambigus, 16 caractères. */
function newConfirmationCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}

// -----------------------------------------------------------------------------
// Réponses
// -----------------------------------------------------------------------------

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function text(body: string, status: number): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex",
    },
  });
}
