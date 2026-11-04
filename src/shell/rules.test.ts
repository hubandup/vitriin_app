// Lancer avec `npm test` (node:test, sans dépendance).
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isAuthUrl, navigationFor, parseBridge, parseLink } from './rules.ts';

const ID = '3f2c1a9e-8b7d-4c6e-9f10-1234567890ab';
const FROM = 'https://app.vitriin.co/magasin/';

test('navigation : seules les pages de l’app restent dans l’app', () => {
  assert.equal(navigationFor('https://app.vitriin.co/v/p/x', true), 'load');
  assert.equal(navigationFor('https://app.vitriin.co/magasin/', true), 'load');
  assert.equal(navigationFor('https://app.vitriin.co/auth/?next=/v/', true), 'load');
  assert.equal(navigationFor('https://app.vitriin.co/centrale/', true), 'external');
  assert.equal(navigationFor('https://www.vitriin.fr/cgu', true), 'external');
  assert.equal(navigationFor('https://www.google.com/maps/dir/', true), 'external');
  assert.equal(navigationFor('tel:+33400000000', true), 'external');
  assert.equal(navigationFor('mailto:a@b.fr', true), 'external');
  assert.equal(navigationFor('https://app.vitriin.co.evil.com/v/', true), 'external');
  assert.equal(navigationFor('javascript:alert(1)', true), 'block');
  assert.equal(navigationFor('intent://x#Intent;end', true), 'block');
  assert.equal(navigationFor('file:///etc/passwd', true), 'block');
  assert.equal(navigationFor('https://www.openstreetmap.org/export/embed.html', false), 'load');
});

test('autorisation : Facebook et Google uniquement', () => {
  assert.ok(isAuthUrl('https://www.facebook.com/v23.0/dialog/oauth?client_id=1'));
  assert.ok(isAuthUrl('https://accounts.google.com/o/oauth2/v2/auth?x=1'));
  assert.ok(!isAuthUrl('http://www.facebook.com/dialog'));
  assert.ok(!isAuthUrl('https://www.facebook.com.evil.com/dialog'));
  assert.ok(!isAuthUrl('https://evil.com/?https://www.facebook.com/'));
});

test('liens entrants', () => {
  assert.deepEqual(parseLink(`vitriin://v/p/${ID}`), { kind: 'open', space: 'client', path: `/v/p/${ID}` });
  assert.deepEqual(parseLink('https://app.vitriin.co/v/m/salon-du-velo/'), { kind: 'open', space: 'client', path: '/v/m/salon-du-velo' });
  assert.deepEqual(parseLink('vitriin://v'), { kind: 'open', space: 'client', path: '/v/' });
  assert.deepEqual(parseLink(`https://app.vitriin.co/magasin/?promo=${ID}&x=1`), { kind: 'open', space: 'magasin', path: `/magasin/?promo=${ID}` });
  assert.deepEqual(parseLink('https://app.vitriin.co/magasin/?promo=../../x'), { kind: 'open', space: 'magasin', path: '/magasin/' });
  assert.equal(parseLink('vitriin://v/p/pas-un-id'), null);
  assert.equal(parseLink('https://app.vitriin.co/manager/'), null);
  assert.equal(parseLink('https://evil.com/v/'), null);
});

test('retour d’autorisation : champs filtrés et réencodés', () => {
  assert.deepEqual(parseLink('vitriin://oauth?oauth=ok&count=2&token=secret'), { kind: 'oauth', path: '/magasin/?oauth=ok&count=2' });
  assert.deepEqual(parseLink('vitriin://oauth?oauth=error&message=Page%20refus%C3%A9e%20%26%20x'), { kind: 'oauth', path: '/magasin/?oauth=error&message=Page%20refus%C3%A9e%20%26%20x' });
  assert.equal(parseLink('vitriin://oauth?oauth=pirate'), null);
  assert.equal(parseLink('vitriin://oauth'), null);
});

test('pont web : origine et contenu contrôlés', () => {
  assert.deepEqual(parseBridge('{"t":"state","tabs":true,"tab":"home","badge":3,"dark":false}', FROM), { t: 'state', tabs: true, tab: 'home', badge: 3, dark: false });
  assert.equal(parseBridge('{"t":"push"}', 'https://www.openstreetmap.org/'), null);
  assert.equal(parseBridge('{"t":"auth","url":"https://evil.com/"}', FROM), null);
  assert.deepEqual(parseBridge('{"t":"auth","url":"https://www.facebook.com/dialog/oauth"}', FROM), { t: 'auth', url: 'https://www.facebook.com/dialog/oauth' });
  assert.equal(parseBridge('{"t":"space","to":"manager"}', FROM), null);
  assert.equal(parseBridge('pas du json', FROM), null);
});
