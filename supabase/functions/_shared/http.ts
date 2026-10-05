// Réponses HTTP, CORS, et la page de confirmation du retour OAuth.

import { env } from "./env.ts";
import { redact } from "./meta.ts";

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = env.allowedOrigins.includes("*")
    ? "*"
    : env.allowedOrigins.includes(origin)
    ? origin
    : env.allowedOrigins[0] ?? "";

  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Vary": "Origin",
  };
}

export function preflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}

export function json(
  req: Request,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

export function fail(
  req: Request,
  status: number,
  message: string,
  extra?: Record<string, unknown>,
): Response {
  return json(req, { error: redact(message), ...extra }, status);
}

/**
 * Journalisation. Passe systématiquement par redact() : une valeur interpolée
 * dans un message d'erreur peut très bien contenir un token sans qu'on l'ait
 * voulu.
 */
export function log(
  level: "info" | "warn" | "error",
  fn: string,
  message: string,
  context: Record<string, unknown> = {},
): void {
  const safe: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    safe[key] = typeof value === "string" ? redact(value) : value;
  }
  console[level === "warn" ? "warn" : level === "error" ? "error" : "log"](
    JSON.stringify({ fn, msg: redact(message), ...safe }),
  );
}

// -----------------------------------------------------------------------------
// Page de confirmation du retour OAuth
// -----------------------------------------------------------------------------
// Le callback s'exécute dans un navigateur, pas dans l'app : Meta y redirige
// le commerçant. Il faut donc lui rendre quelque chose de lisible.
//
// Une page HTML plutôt qu'un deep link, parce qu'un deep link ne tient pas en
// développement : Expo Go sert l'app sous un schéma exp:// qui change à chaque
// session, impossible à figer dans un secret. La page, elle, marche partout —
// Expo Go, build natif, navigateur — sans rien reconfigurer.
//
// Si APP_RETURN_URL est posé, on ajoute un bouton de retour. Sinon la page se
// suffit à elle-même : le commerçant revient à l'app à la main.

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function confirmationPage(options: {
  ok: boolean;
  title: string;
  message: string;
  /** Noms des comptes connectés, affichés en liste. */
  accounts?: string[];
  status?: number;
}): Response {
  const { ok, title, message, accounts = [], status = ok ? 200 : 400 } = options;

  const accent = ok ? "#0c9875" : "#e5087e";

  const accountList = accounts.length > 0
    ? `<ul class="accounts">${
      accounts.map((a) => `<li>${escapeHtml(a)}</li>`).join("")
    }</ul>`
    : "";

  // Le bouton de retour n'est rendu que si APP_RETURN_URL est configuré. En
  // développement il ne l'est pas, et c'est le cas normal.
  const returnButton = env.appReturnUrl
    ? `<a class="button" href="${escapeHtml(env.appReturnUrl)}">Revenir à Vitriin</a>`
    : `<p class="hint">Vous pouvez fermer cette fenêtre et revenir à l'application.</p>`;

  const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${escapeHtml(title)} — Vitriin</title>
<style>
  :root {
    --ink: #2D2D2D;
    --muted: #888888;
    --line: #EEECE8;
    --cream: #f5ecd3;
    --accent: ${accent};
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    background: var(--cream);
    color: var(--ink);
    font-family: "DM Sans", -apple-system, BlinkMacSystemFont, "Segoe UI",
                 Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.5;
  }
  .card {
    width: 100%;
    max-width: 420px;
    background: #fff;
    border: 1px solid var(--line);
    border-radius: 20px;
    overflow: hidden;
  }
  /* Le dégradé est la signature de la marque : il structure la carte. */
  .bar { height: 6px; background: linear-gradient(to right, #e5087e, #951b81); }
  .body { padding: 32px 28px; }
  .mark {
    font-size: 13px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--muted);
    margin: 0 0 20px;
  }
  h1 {
    margin: 0 0 10px;
    font-size: 23px;
    font-weight: 700;
    color: var(--accent);
  }
  p { margin: 0 0 16px; font-size: 15px; }
  .hint { color: var(--muted); font-size: 14px; margin-bottom: 0; }
  .accounts {
    list-style: none;
    margin: 0 0 20px;
    padding: 0;
    border-top: 1px solid var(--line);
  }
  .accounts li {
    padding: 11px 0;
    border-bottom: 1px solid var(--line);
    font-size: 15px;
    font-weight: 500;
  }
  .button {
    display: block;
    text-align: center;
    padding: 14px 20px;
    border-radius: 12px;
    background: linear-gradient(to right, #e5087e, #951b81);
    color: #fff;
    font-weight: 700;
    font-size: 15px;
    text-decoration: none;
  }
</style>
</head>
<body>
  <main class="card">
    <div class="bar"></div>
    <div class="body">
      <p class="mark">Vitriin</p>
      <h1>${escapeHtml(title)}</h1>
      <p>${escapeHtml(message)}</p>
      ${accountList}
      ${returnButton}
    </div>
  </main>
</body>
</html>`;

  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      // La page apparaît en fin de flux OAuth : on la verrouille.
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
    },
  });
}
