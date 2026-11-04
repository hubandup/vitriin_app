/**
 * Règles de la coquille mobile : ce que l'app affiche, ce qu'elle ouvre ailleurs,
 * ce qu'elle accepte des pages web et des liens entrants.
 * Aucun import React Native : ce fichier se teste seul (`npm test`).
 * Le `URL` de Hermes est incomplet, d'où le découpage à la main.
 */
export const WEB_ORIGIN = 'https://app.vitriin.co';
export const APP_SCHEME = 'vitriin';
export const OAUTH_RETURN = `${APP_SCHEME}://oauth`;

export type Space = 'client' | 'magasin';

export const SPACE_PATH: Record<Space, string> = { client: '/v/', magasin: '/magasin/' };

const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const IN_APP_PATH = /^\/(v|magasin|auth)(\/|$)/;
const AUTH_HOSTS = ['www.facebook.com', 'm.facebook.com', 'facebook.com', 'accounts.google.com'];

/** Coupe une URL absolue sans dépendre de `URL`. */
export function splitUrl(url: string) {
  const m = /^([a-z][a-z0-9+.-]*):(?:\/\/([^/?#]*))?([^?#]*)(?:\?([^#]*))?/i.exec(url);
  if (!m) return null;
  return { scheme: m[1].toLowerCase(), host: (m[2] ?? '').toLowerCase(), path: m[3] ?? '', query: m[4] ?? '' };
}

function queryParams(query: string) {
  const out: Record<string, string> = {};
  for (const part of query.split('&')) {
    const i = part.indexOf('=');
    if (i < 1) continue;
    try {
      out[decodeURIComponent(part.slice(0, i))] = decodeURIComponent(part.slice(i + 1).replace(/\+/g, ' '));
    } catch {
      /* paramètre mal encodé : ignoré */
    }
  }
  return out;
}

/** Une navigation du cadre principal : reste dans l'app, part à l'extérieur, ou est refusée. */
export function navigationFor(url: string, topFrame: boolean): 'load' | 'external' | 'block' {
  if (!topFrame) return 'load';
  const u = splitUrl(url);
  if (!u) return 'block';
  if (u.scheme === 'about' || u.scheme === 'blob') return 'load';
  if (u.scheme === 'https' && u.host === 'app.vitriin.co') return IN_APP_PATH.test(u.path) ? 'load' : 'external';
  if (u.scheme === 'https' || u.scheme === 'mailto' || u.scheme === 'tel') return 'external';
  return 'block';
}

/** Seules les pages d'autorisation Facebook et Google passent par le navigateur système. */
export function isAuthUrl(url: string) {
  const u = splitUrl(url);
  return !!u && u.scheme === 'https' && AUTH_HOSTS.includes(u.host);
}

export type Link =
  | { kind: 'open'; space: Space; path: string }
  | { kind: 'oauth'; path: string };

/** Retour d'autorisation : on ne garde que l'issue, le nombre de comptes et le message. */
function oauthLink(query: string): Link | null {
  const q = queryParams(query);
  if (!['ok', 'error', 'gbp-pick'].includes(q.oauth ?? '')) return null;
  const parts = [`oauth=${encodeURIComponent(q.oauth)}`];
  if (/^\d{1,3}$/.test(q.count ?? '')) parts.push(`count=${q.count}`);
  if (q.message) parts.push(`message=${encodeURIComponent(q.message.slice(0, 300))}`);
  return { kind: 'oauth', path: `/magasin/?${parts.join('&')}` };
}

function openLink(path: string, query: string): Link | null {
  const clean = path.replace(/\/+$/, '') || '/';
  const q = queryParams(query);
  if (clean === '/v') return { kind: 'open', space: 'client', path: '/v/' };
  if (new RegExp(`^/v/(promos|suivies|profil|p/${UUID}|m/[a-z0-9-]{1,80})$`, 'i').test(clean)) {
    return { kind: 'open', space: 'client', path: clean };
  }
  if (clean === '/magasin') {
    const id = new RegExp(`^${UUID}$`, 'i');
    if (q.promo && id.test(q.promo)) return { kind: 'open', space: 'magasin', path: `/magasin/?promo=${q.promo}` };
    if (q.support && id.test(q.support)) return { kind: 'open', space: 'magasin', path: `/magasin/?support=${q.support}` };
    return { kind: 'open', space: 'magasin', path: '/magasin/' };
  }
  return null;
}

/** Lien entrant (schéma vitriin://, lien universel, notification) vers un écran autorisé. */
export function parseLink(url: string): Link | null {
  const u = splitUrl(url);
  if (!u) return null;
  if (u.scheme === APP_SCHEME) {
    if (u.host === 'oauth') return oauthLink(u.query);
    return openLink(`/${u.host}${u.path}`, u.query);
  }
  if (u.scheme === 'https' && u.host === 'app.vitriin.co') return openLink(u.path, u.query);
  return null;
}

export type BridgeMessage =
  | { t: 'state'; tabs: boolean; tab: string | null; badge: number; dark: boolean }
  | { t: 'auth'; url: string }
  | { t: 'share'; title: string; text: string; url: string }
  | { t: 'space'; to: Space }
  | { t: 'push' }
  | { t: 'back-unhandled' };

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.slice(0, max) : '');

/** Message d'une page web : l'origine est vérifiée, chaque champ est retypé. */
export function parseBridge(raw: string, fromUrl: string): BridgeMessage | null {
  const from = splitUrl(fromUrl);
  if (!from || from.scheme !== 'https' || from.host !== 'app.vitriin.co') return null;
  let m: any;
  try {
    m = JSON.parse(raw);
  } catch {
    return null;
  }
  switch (m?.t) {
    case 'state':
      return {
        t: 'state',
        tabs: m.tabs === true,
        tab: typeof m.tab === 'string' ? m.tab.slice(0, 20) : null,
        badge: Number.isInteger(m.badge) && m.badge > 0 ? Math.min(m.badge, 99) : 0,
        dark: m.dark === true,
      };
    case 'auth':
      return isAuthUrl(str(m.url, 4000)) ? { t: 'auth', url: m.url } : null;
    case 'share':
      return { t: 'share', title: str(m.title, 200), text: str(m.text, 500), url: str(m.url, 500) };
    case 'space':
      return m.to === 'client' || m.to === 'magasin' ? { t: 'space', to: m.to } : null;
    case 'push':
      return { t: 'push' };
    case 'back-unhandled':
      return { t: 'back-unhandled' };
    default:
      return null;
  }
}
