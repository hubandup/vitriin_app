#!/usr/bin/env bash
#
# smoke-meta.sh — teste la plomberie Meta de bout en bout, sans interface.
#
#   Usage :
#     cp scripts/smoke-meta.env.example scripts/smoke-meta.env
#     # renseigner les valeurs, puis :
#     ./scripts/smoke-meta.sh                 # parcours complet
#     ./scripts/smoke-meta.sh leaks           # uniquement les tests d'étanchéité
#     ./scripts/smoke-meta.sh publish <uuid>  # republier une activation
#
# Le fichier smoke-meta.env est ignoré par git (motif *.env).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/smoke-meta.env" ] && . "$HERE/smoke-meta.env"

: "${SUPABASE_URL:?Manque SUPABASE_URL (https://zjugauidrijghesgsmap.supabase.co)}"
: "${SUPABASE_ANON_KEY:?Manque SUPABASE_ANON_KEY}"
: "${TEST_EMAIL:?Manque TEST_EMAIL}"
: "${TEST_PASSWORD:?Manque TEST_PASSWORD}"

REST="$SUPABASE_URL/rest/v1"
FN="$SUPABASE_URL/functions/v1"

bold()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
ko()    { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info()  { printf '    %s\n' "$*"; }

need_jq() {
  command -v jq >/dev/null || { echo "jq est requis : brew install jq"; exit 1; }
}
need_jq

# -----------------------------------------------------------------------------
# 1. Un JWT utilisateur, sans interface
# -----------------------------------------------------------------------------
login() {
  bold "1. Authentification — $TEST_EMAIL"
  local response
  response=$(curl -sS -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg e "$TEST_EMAIL" --arg p "$TEST_PASSWORD" \
          '{email:$e, password:$p}')")

  JWT=$(echo "$response" | jq -r '.access_token // empty')
  if [ -z "$JWT" ]; then
    ko "Connexion refusée"
    echo "$response" | jq .
    exit 1
  fi
  USER_ID=$(echo "$response" | jq -r '.user.id')
  ok "Connecté — user_id $USER_ID"
}

auth_curl() {
  curl -sS -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $JWT" "$@"
}

anon_curl() {
  curl -sS -H "apikey: $SUPABASE_ANON_KEY" "$@"
}

# -----------------------------------------------------------------------------
# 2. Un magasin — create_store est l'unique porte d'entrée prévue par le schéma
# -----------------------------------------------------------------------------
ensure_store() {
  bold "2. Magasin"

  if [ -n "${STORE_ID:-}" ]; then
    ok "Fourni par l'environnement — $STORE_ID"
    return
  fi

  local existing
  existing=$(auth_curl "$REST/store_members?select=store_id&limit=1" | jq -r '.[0].store_id // empty')
  if [ -n "$existing" ]; then
    STORE_ID="$existing"
    ok "Magasin existant — $STORE_ID"
    return
  fi

  local slug="smoke-$(date +%s)"
  local created
  created=$(auth_curl -X POST "$REST/rpc/create_store" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$slug" '{p_slug:$s, p_name:"Magasin de test Vitriin", p_city:"Paris"}')")

  STORE_ID=$(echo "$created" | jq -r '.id // empty')
  [ -n "$STORE_ID" ] || { ko "Création impossible"; echo "$created" | jq .; exit 1; }
  ok "Magasin créé — $STORE_ID ($slug)"
}

# -----------------------------------------------------------------------------
# 3. Ouvrir le flux OAuth
# -----------------------------------------------------------------------------
oauth_start() {
  bold "3. Démarrage OAuth"

  local response
  response=$(auth_curl -X POST "$FN/meta-oauth-start" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$STORE_ID" '{store_id:$s}')")

  AUTHORIZE_URL=$(echo "$response" | jq -r '.authorize_url // empty')
  if [ -z "$AUTHORIZE_URL" ]; then
    ko "Pas d'URL d'autorisation"
    echo "$response" | jq .
    exit 1
  fi

  ok "URL générée (valable 10 minutes)"
  echo
  echo "$AUTHORIZE_URL"
  echo
  info "Ouvrez cette URL dans un navigateur et autorisez avec votre compte Facebook."
  info "C'est aussi le moment d'enregistrer la vidéo pour l'App Review."
  command -v open >/dev/null && read -r -p "    Ouvrir maintenant ? [o/N] " yn \
    && [ "${yn:-}" = "o" ] && open "$AUTHORIZE_URL"

  read -r -p "    Appuyez sur Entrée une fois la page de confirmation affichée… "
}

# -----------------------------------------------------------------------------
# 4. Étanchéité — le test qui compte
# -----------------------------------------------------------------------------
check_leaks() {
  bold "4. Étanchéité des tokens"

  local rows
  rows=$(auth_curl "$REST/social_accounts?select=*&store_id=eq.$STORE_ID")
  local count
  count=$(echo "$rows" | jq 'length')
  info "$count compte(s) visible(s) par le membre du magasin"
  echo "$rows" | jq -r '.[] | "    · \(.display_name) — \(.channel) — \(.status)"'

  # Aucune clé ne doit ressembler de près ou de loin à un token.
  local suspect
  suspect=$(echo "$rows" | jq -r '[.[] | keys[]] | unique
            | map(select(test("token|secret|cipher|credential"; "i"))) | join(", ")')
  if [ -z "$suspect" ]; then
    ok "Aucune colonne de token exposée"
  else
    ko "COLONNES SUSPECTES EXPOSÉES : $suspect"
    exit 1
  fi

  # La RPC de lecture du chiffré doit être hors de portée d'un JWT utilisateur.
  local account_id rpc
  account_id=$(echo "$rows" | jq -r '.[0].id // empty')
  if [ -n "$account_id" ]; then
    rpc=$(auth_curl -X POST "$REST/rpc/social_account_token_get" \
      -H "Content-Type: application/json" \
      -d "$(jq -nc --arg a "$account_id" '{p_account_id:$a}')")
    if echo "$rpc" | jq -e '.code? // .message?' >/dev/null 2>&1; then
      ok "social_account_token_get refusée à authenticated"
      info "$(echo "$rpc" | jq -r '.message // .code')"
    else
      ko "LA RPC DE LECTURE DU CHIFFRÉ RÉPOND À UN JWT UTILISATEUR"
      exit 1
    fi
  fi

  # anon ne doit rien voir du tout.
  local anon_rows
  anon_rows=$(anon_curl "$REST/social_accounts?select=id")
  if echo "$anon_rows" | jq -e 'type == "array" and length == 0' >/dev/null 2>&1; then
    ok "anon ne voit aucun compte"
  elif echo "$anon_rows" | jq -e '.code? // .message?' >/dev/null 2>&1; then
    ok "anon refusé — $(echo "$anon_rows" | jq -r '.message // .code')"
  else
    ko "ANON VOIT DES COMPTES"
    echo "$anon_rows" | jq .
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# 5. Tests négatifs
# -----------------------------------------------------------------------------
check_negatives() {
  bold "5. Tests négatifs"

  local tampered
  tampered=$(curl -sS -o /dev/null -w '%{http_code}' \
    "$FN/meta-oauth-callback?code=faux&state=charge.signature-bidon")
  [ "$tampered" = "400" ] \
    && ok "State forgé rejeté (HTTP 400)" \
    || ko "State forgé : HTTP $tampered, attendu 400"

  local nostate
  nostate=$(curl -sS -o /dev/null -w '%{http_code}' "$FN/meta-oauth-callback")
  [ "$nostate" = "400" ] \
    && ok "Callback sans paramètres rejeté (HTTP 400)" \
    || ko "Callback nu : HTTP $nostate, attendu 400"

  local nojwt
  nojwt=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$FN/meta-oauth-start" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
    -d '{"store_id":"00000000-0000-4000-8000-000000000000"}')
  [ "$nojwt" = "401" ] \
    && ok "meta-oauth-start sans JWT rejeté (HTTP 401)" \
    || ko "Sans JWT : HTTP $nojwt, attendu 401"

  local foreign
  foreign=$(auth_curl -X POST "$FN/meta-oauth-start" \
    -H "Content-Type: application/json" \
    -d '{"store_id":"00000000-0000-4000-8000-000000000000"}' \
    -o /dev/null -w '%{http_code}')
  [ "$foreign" = "403" ] \
    && ok "Magasin d'un tiers refusé (HTTP 403)" \
    || ko "Magasin tiers : HTTP $foreign, attendu 403"
}

# -----------------------------------------------------------------------------
# 6. Une promo, puis publication
# -----------------------------------------------------------------------------
make_promotion() {
  bold "6. Promotion de test"

  local media="${TEST_MEDIA_URL:-}"
  [ -n "$media" ] || info "TEST_MEDIA_URL absent : Instagram échouera (c'est attendu)."

  local starts ends
  starts=$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')
  ends=$(date -u -v+7d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '7 days' '+%Y-%m-%dT%H:%M:%SZ')

  local promo
  promo=$(auth_curl -X POST "$REST/promotions" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$(jq -nc --arg st "$STORE_ID" --arg a "$starts" --arg b "$ends" --arg m "$media" '
          {created_by_store_id:$st,
           title:"Test Vitriin — plomberie Meta",
           mechanic:"-30%",
           description:"Publication de test émise par smoke-meta.sh. Ignorez ce message.",
           media_url:(if $m == "" then null else $m end),
           starts_at:$a, ends_at:$b, status:"active"}')")

  PROMOTION_ID=$(echo "$promo" | jq -r '.[0].id // empty')
  [ -n "$PROMOTION_ID" ] || { ko "Création de la promo impossible"; echo "$promo" | jq .; exit 1; }
  ok "Promotion — $PROMOTION_ID"

  local activation
  activation=$(auth_curl -X POST "$REST/store_promotions" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    -d "$(jq -nc --arg p "$PROMOTION_ID" --arg s "$STORE_ID" \
          '{promotion_id:$p, store_id:$s}')")

  STORE_PROMOTION_ID=$(echo "$activation" | jq -r '.[0].id // empty')
  [ -n "$STORE_PROMOTION_ID" ] || { ko "Activation impossible"; echo "$activation" | jq .; exit 1; }

  # La promo n'est pas obligatoire : elle naît `pending`, le PDV doit activer.
  auth_curl -X PATCH "$REST/store_promotions?id=eq.$STORE_PROMOTION_ID" \
    -H "Content-Type: application/json" \
    -d '{"status":"active"}' >/dev/null
  ok "Activation — $STORE_PROMOTION_ID (active)"
}

publish() {
  bold "7. Publication"

  local response
  response=$(auth_curl -X POST "$FN/meta-publish" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$STORE_PROMOTION_ID" '{store_promotion_id:$s}')")

  echo "$response" | jq .
  echo "$response" | jq -r '.results[]? |
    "    \(if .status == "published" then "✓" else "✗" end) \(.channel) — \(.account // "?") — \(.status)\(if .error then ": " + .error else "" end)"'

  bold "8. Idempotence — second appel, aucun doublon attendu"
  auth_curl -X POST "$FN/meta-publish" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$STORE_PROMOTION_ID" '{store_promotion_id:$s}')" \
    | jq -r '.results[]? | "    \(.channel) — \(.status): \(.error // "republié ?!")"'

  bold "9. Table publications"
  auth_curl "$REST/publications?select=channel,status,external_post_id,error_message&store_promotion_id=eq.$STORE_PROMOTION_ID" | jq .
}

health() {
  bold "10. Santé des comptes"
  auth_curl -X POST "$FN/meta-health-check" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$STORE_ID" '{store_id:$s}')" \
    | jq -r '"    \(.checked) vérifié(s), \(.revoked) révoqué(s)", (.results[]? | "    · \(.display_name) — \(.status)")'
}

# -----------------------------------------------------------------------------

case "${1:-all}" in
  leaks)
    login; ensure_store; check_leaks ;;
  negatives)
    login; ensure_store; check_negatives ;;
  publish)
    login; ensure_store
    STORE_PROMOTION_ID="${2:?Usage : ./smoke-meta.sh publish <store_promotion_id>}"
    publish ;;
  health)
    login; ensure_store; health ;;
  all)
    login
    ensure_store
    check_negatives
    oauth_start
    check_leaks
    make_promotion
    publish
    health
    bold "Terminé." ;;
  *)
    echo "Usage : $0 [all|leaks|negatives|publish <id>|health]"; exit 1 ;;
esac
