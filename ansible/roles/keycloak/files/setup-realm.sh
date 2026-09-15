#!/usr/bin/env bash
#
# Configure un realm OdyssAI via l'Admin REST API. Idempotent.
#
#   KC_ADMIN_CLIENT_ID=... KC_ADMIN_CLIENT_SECRET='...' $0 odyssai-prod
#
# Le service account est a privilegier : un compte humain protege par MFA ne
# peut pas passer par le direct grant. Autres variables : KC_URL,
# KC_ADMIN_REALM, API_BASE_URL, WEB_BASE_URL, API_CLIENT_ID, DISPLAY_NAME,
# EXTRA_REDIRECT_URIS, LOGIN_THEME, SSL_REQUIRED (passer a "external" si le
# proxy ne transmet pas X-Forwarded-Proto, sinon boucle de redirection).
#
# apps/api est le seul client, confidentiel, en Authorization Code + PKCE :
# aucun mot de passe ne transite par l'API.
#
set -euo pipefail

KC_URL="${KC_URL:-https://sso.joachimjasmin.com}"
KC_URL="${KC_URL%/}"
KC_ADMIN_REALM="${KC_ADMIN_REALM:-master}"
KC_ADMIN_USER="${KC_ADMIN_USER:-}"
KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-}"
KC_ADMIN_CLIENT_ID="${KC_ADMIN_CLIENT_ID:-}"
KC_ADMIN_CLIENT_SECRET="${KC_ADMIN_CLIENT_SECRET:-}"
API_CLIENT_ID="${API_CLIENT_ID:-odyssai-api}"

# SMTP_HOST est la variable pivot : vide, verifyEmail reste faux, sinon un
# compte non verifie resterait bloque sans moyen de se debloquer.
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_FROM="${SMTP_FROM:-}"
SMTP_FROM_NAME="${SMTP_FROM_NAME:-$DISPLAY_NAME}"
SMTP_USER="${SMTP_USER:-$SMTP_FROM}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
DISPLAY_NAME="${DISPLAY_NAME:-OdyssAI}"
# Repasser a "keycloak" sur une instance sans le theme : Keycloak retombe sur
# ses pages par defaut sans signaler que le theme est introuvable.
LOGIN_THEME="${LOGIN_THEME:-odyssai}"
SSL_REQUIRED="${SSL_REQUIRED:-all}"
REALM="${1:-}"

if [[ -z "$REALM" ]]; then
  echo "usage: KC_ADMIN_PASSWORD='...' $0 <realm>   (ex: odyssai-dev)" >&2
  exit 2
fi

# Origines choisies d'apres le realm vise, pas d'apres la machine qui lance le
# script : le realm de dev sert a la fois la copie deployee et le poste du
# developpeur. Chaque URI reste exacte, jamais un joker.
case "$REALM" in
  *-prod)
    API_BASE_URL="${API_BASE_URL:-https://api.odyssai.app}"
    WEB_BASE_URL="${WEB_BASE_URL:-https://odyssai.app}"
    # Pas de localhost en production.
    EXTRA_REDIRECT_URIS="${EXTRA_REDIRECT_URIS:-}"
    EXTRA_POST_LOGOUT_URIS="${EXTRA_POST_LOGOUT_URIS:-}"
    ;;
  *)
    API_BASE_URL="${API_BASE_URL:-https://api-dev.odyssai.app}"
    WEB_BASE_URL="${WEB_BASE_URL:-https://dev.odyssai.app}"
    EXTRA_REDIRECT_URIS="${EXTRA_REDIRECT_URIS:-http://localhost:3001/auth/callback}"
    EXTRA_POST_LOGOUT_URIS="${EXTRA_POST_LOGOUT_URIS:-http://localhost:3000}"
    ;;
esac
API_BASE_URL="${API_BASE_URL%/}"
WEB_BASE_URL="${WEB_BASE_URL%/}"
if [[ -z "$KC_ADMIN_CLIENT_SECRET" && -z "$KC_ADMIN_PASSWORD" ]]; then
  cat >&2 <<'USAGE'
Aucun identifiant d'administration.

  Service account (recommande) :
    KC_ADMIN_CLIENT_ID=odyssai-provisioner KC_ADMIN_CLIENT_SECRET='...'

  Compte humain, impossible si le compte porte du MFA :
    KC_ADMIN_USER=admin KC_ADMIN_PASSWORD='...'
USAGE
  exit 2
fi
for bin in curl jq; do
  command -v "$bin" >/dev/null || { echo "$bin est requis" >&2; exit 2; }
done

log() { printf '   %s\n' "$*" >&2; }
step() { printf '\n== %s\n' "$*" >&2; }

# ---------------------------------------------------------------- token admin

step "Authentification sur $KC_URL (realm $KC_ADMIN_REALM)"

TOKEN_ENDPOINT="$KC_URL/realms/$KC_ADMIN_REALM/protocol/openid-connect/token"

# Rappelee apres la creation d'un realm : les droits sur le nouveau realm ne
# sont pas dans un jeton emis avant, et tout ce qui suit repondrait 403.
authenticate() {
if [[ -n "$KC_ADMIN_CLIENT_SECRET" ]]; then
  AUTH_MODE="service account $KC_ADMIN_CLIENT_ID"
  AUTH_RESPONSE="$(curl -sS -X POST "$TOKEN_ENDPOINT" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=$KC_ADMIN_CLIENT_ID" \
    --data-urlencode "client_secret=$KC_ADMIN_CLIENT_SECRET")"
else
  AUTH_MODE="compte $KC_ADMIN_USER"
  AUTH_RESPONSE="$(curl -sS -X POST "$TOKEN_ENDPOINT" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode 'client_id=admin-cli' \
    --data-urlencode "username=$KC_ADMIN_USER" \
    --data-urlencode "password=$KC_ADMIN_PASSWORD")"
fi

TOKEN="$(jq -re '.access_token // empty' <<<"$AUTH_RESPONSE" 2>/dev/null || true)"

if [[ -z "$TOKEN" ]]; then
  echo "echec de l'authentification ($AUTH_MODE) sur $KC_URL/realms/$KC_ADMIN_REALM" >&2
  echo "reponse : $(jq -rc '{error, error_description}' <<<"$AUTH_RESPONSE" 2>/dev/null || echo "$AUTH_RESPONSE")" >&2
  if [[ -z "$KC_ADMIN_CLIENT_SECRET" ]]; then
    echo "un compte protege par MFA ne peut pas passer par le direct grant : utiliser un service account" >&2
  fi
  exit 1
fi
}

authenticate
log "authentifie par $AUTH_MODE"

# api <METHODE> <CHEMIN> [CORPS] : renseigne HTTP_CODE et RESP_BODY. Sans
# sortie standard : une substitution de commande perdrait les deux variables.
HTTP_CODE=""
RESP_BODY=""
LAST_CALL=""
api() {
  local method="$1" path="$2" body="${3:-}" out
  local args=(-sS -w $'\n%{http_code}' -X "$method"
    "$KC_URL$path" -H "Authorization: Bearer $TOKEN")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  LAST_CALL="$method $path"
  out="$(curl "${args[@]}")"
  HTTP_CODE="${out##*$'\n'}"
  RESP_BODY="${out%$'\n'*}"
}

expect() {
  if [[ " $1 " != *" $HTTP_CODE "* ]]; then
    echo "echec sur $LAST_CALL (HTTP $HTTP_CODE) : $RESP_BODY" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------- realm

step "Realm $REALM"

# smtpServer n'accepte que des chaines, port et booleens compris.
if [[ -n "$SMTP_HOST" ]]; then
  SMTP_CONFIG="$(jq -n \
    --arg host "$SMTP_HOST" --arg port "$SMTP_PORT" \
    --arg from "$SMTP_FROM" --arg fromName "$SMTP_FROM_NAME" \
    --arg user "$SMTP_USER" --arg password "$SMTP_PASSWORD" \
    --arg starttls "$([[ "$SMTP_PORT" == "465" ]] && echo false || echo true)" \
    --arg ssl "$([[ "$SMTP_PORT" == "465" ]] && echo true || echo false)" '
    {host: $host, port: $port, from: $from, fromDisplayName: $fromName,
     replyTo: $from, starttls: $starttls, ssl: $ssl,
     auth: (if $user == "" then "false" else "true" end)}
    + (if $user == "" then {} else {user: $user, password: $password} end)')"
  VERIFY_EMAIL=true
  log "SMTP $SMTP_HOST:$SMTP_PORT, expediteur $SMTP_FROM"
else
  SMTP_CONFIG='{}'
  VERIFY_EMAIL=false
  log "SMTP absent : verification d adresse desactivee"
fi

REALM_CONFIG="$(jq -n \
  --argjson smtp "$SMTP_CONFIG" \
  --argjson verify "$VERIFY_EMAIL" \
  --arg realm "$REALM" \
  --arg display "$DISPLAY_NAME" \
  --arg theme "$LOGIN_THEME" \
  --arg ssl "$SSL_REQUIRED" '{
  realm: $realm,
  displayName: $display,
  enabled: true,
  registrationAllowed: true,
  registrationEmailAsUsername: true,
  loginWithEmailAllowed: true,
  duplicateEmailsAllowed: false,
  editUsernameAllowed: false,
  resetPasswordAllowed: true,
  rememberMe: true,

  # Jamais force : la verification sans SMTP enfermerait dehors tout compte
  # cree ensuite.
  verifyEmail: $verify,
  smtpServer: $smtp,

  loginTheme: $theme,
  sslRequired: $ssl,
  internationalizationEnabled: true,
  supportedLocales: ["fr", "en"],
  defaultLocale: "fr",

  passwordPolicy: "length(12) and notUsername(undefined) and notEmail(undefined) and passwordHistory(3)",

  bruteForceProtected: true,
  permanentLockout: false,
  failureFactor: 10,
  waitIncrementSeconds: 60,
  maxFailureWaitSeconds: 900,
  quickLoginCheckMilliSeconds: 1000,
  minimumQuickLoginWaitSeconds: 60,

  accessTokenLifespan: 300,
  accessCodeLifespan: 60,
  ssoSessionIdleTimeout: 1800,
  ssoSessionMaxLifespan: 36000,
  ssoSessionIdleTimeoutRememberMe: 172800,
  ssoSessionMaxLifespanRememberMe: 2592000,

  # Un refresh token ne sert qu une fois : un rejeu invalide la session.
  revokeRefreshToken: true,
  refreshTokenMaxReuse: 0,

  defaultSignatureAlgorithm: "RS256",
  browserSecurityHeaders: {
    contentSecurityPolicy: "frame-src '\''self'\''; frame-ancestors '\''none'\''; object-src '\''none'\''",
    xFrameOptions: "DENY",
    strictTransportSecurity: "max-age=31536000; includeSubDomains"
  }
}')"

api GET "/admin/realms/$REALM"
if [[ "$HTTP_CODE" == "200" ]]; then
  api PUT "/admin/realms/$REALM" "$REALM_CONFIG"
  expect "204"
  log "realm mis a jour"
else
  api POST "/admin/realms" "$REALM_CONFIG"
  expect "201"
  log "realm cree"
  authenticate
  log "jeton renouvele pour prendre les droits sur le nouveau realm"
fi

# --------------------------------------------------------------- user profile

step "Profil utilisateur (formulaire d inscription reduit)"

# firstName et lastName restent declares pour la console compte, mais masques :
# l inscription se limite a l email et au mot de passe.
USER_PROFILE="$(jq -n '{
  attributes: [
    {
      name: "username",
      displayName: "${username}",
      validations: {
        length: { min: 3, max: 255 },
        "username-prohibited-characters": {},
        "up-username-not-idn-homograph": {}
      },
      permissions: { view: ["admin", "user"], edit: ["admin"] },
      multivalued: false
    },
    {
      name: "email",
      displayName: "${email}",
      validations: { email: {}, length: { max: 255 } },
      # Sans ca, l inscription rend un input text : pas de clavier courriel.
      annotations: { inputType: "email" },
      required: { roles: ["user"] },
      permissions: { view: ["admin", "user"], edit: ["admin", "user"] },
      multivalued: false
    },
    {
      name: "firstName",
      displayName: "${firstName}",
      validations: { length: { max: 255 }, "person-name-prohibited-characters": {} },
      permissions: { view: ["admin"], edit: ["admin"] },
      multivalued: false
    },
    {
      name: "lastName",
      displayName: "${lastName}",
      validations: { length: { max: 255 }, "person-name-prohibited-characters": {} },
      permissions: { view: ["admin"], edit: ["admin"] },
      multivalued: false
    }
  ],
  groups: [
    {
      name: "user-metadata",
      displayHeader: "User metadata",
      displayDescription: "Attributes, which refer to user metadata"
    }
  ]
  # Pas de unmanagedAttributePolicy : son absence est deja la plus stricte.
}')"

api PUT "/admin/realms/$REALM/users/profile" "$USER_PROFILE"
expect "200 204"
log "profil applique (email requis, nom et prenom masques)"

# ----------------------------------------------------------------- role player

step "Role realm player"

api GET "/admin/realms/$REALM/roles/player"
if [[ "$HTTP_CODE" != "200" ]]; then
  api POST "/admin/realms/$REALM/roles" \
    '{"name":"player","description":"Joueur OdyssAI"}'
  expect "201"
  log "role cree"
  api GET "/admin/realms/$REALM/roles/player"
  expect "200"
else
  log "role deja present"
fi
PLAYER_ROLE="$RESP_BODY"

api GET "/admin/realms/$REALM/roles/default-roles-$REALM"
expect "200"
DEFAULT_ROLE_ID="$(jq -re '.id' <<<"$RESP_BODY")"

api GET "/admin/realms/$REALM/roles-by-id/$DEFAULT_ROLE_ID/composites"
expect "200"

if ! jq -e 'any(.[]; .name == "player")' <<<"$RESP_BODY" >/dev/null; then
  api POST "/admin/realms/$REALM/roles-by-id/$DEFAULT_ROLE_ID/composites" \
    "$(jq -n --argjson r "$PLAYER_ROLE" '[$r]')"
  expect "204"
  log "role ajoute aux roles par defaut"
else
  log "role deja dans les roles par defaut"
fi

# ---------------------------------------------------------------------- client

step "Client $API_CLIENT_ID"

REDIRECT_URIS="$(jq -n \
  --arg main "$API_BASE_URL/auth/callback" \
  --arg extra "$EXTRA_REDIRECT_URIS" '
    [$main] + ($extra | split(",") | map(select(length > 0)))
    | unique')"
log "redirect_uri : $(jq -r 'join(", ")' <<<"$REDIRECT_URIS")"

# Separees par ## et non par une virgule.
POST_LOGOUT_URIS="$(jq -rn \
  --arg web "$WEB_BASE_URL" \
  --arg extra "$EXTRA_POST_LOGOUT_URIS" '
    # Avec et sans barre finale : la comparaison est exacte, et
    # new URL(...).toString() cote apps/api ajoute la barre.
    def variants: rtrimstr("/") | [., . + "/"];
    ([$web] + ($extra | split(",") | map(select(length > 0))))
    | map(variants) | flatten | unique | join("##")')"
log "post_logout_redirect_uri : ${POST_LOGOUT_URIS//\#\#/, }"

CLIENT_CONFIG="$(jq -n \
  --arg id "$API_CLIENT_ID" \
  --argjson redirect "$REDIRECT_URIS" \
  --arg postLogout "$POST_LOGOUT_URIS" \
  --arg web "$WEB_BASE_URL" '{
  clientId: $id,
  name: "OdyssAI API",
  enabled: true,
  protocol: "openid-connect",
  publicClient: false,
  standardFlowEnabled: true,

  # Le direct grant ferait transiter les mots de passe par l API.
  directAccessGrantsEnabled: false,
  implicitFlowEnabled: false,
  serviceAccountsEnabled: false,

  redirectUris: $redirect,
  webOrigins: [],
  rootUrl: "",
  # Le retour propose quand Keycloak a perdu le contexte, au bout d un lien
  # de verification par exemple. Un client par environnement, donc.
  baseUrl: $web,

  frontchannelLogout: false,
  attributes: {
    # PKCE meme sur un client confidentiel, exige par OAuth 2.1.
    "pkce.code.challenge.method": "S256",
    "post.logout.redirect.uris": $postLogout,
    "backchannel.logout.session.required": "true",
    "client.use.lightweight.access.token.enabled": "false",
    "access.token.lifespan": "300"
  }
}')"

api GET "/admin/realms/$REALM/clients?clientId=$API_CLIENT_ID"
expect "200"
# Pas de -e : jq sort en 4 sur un filtre vide, et "client absent" est nominal.
CLIENT_UUID="$(jq -r '.[0].id // empty' <<<"$RESP_BODY")"

if [[ -n "$CLIENT_UUID" ]]; then
  api PUT "/admin/realms/$REALM/clients/$CLIENT_UUID" "$CLIENT_CONFIG"
  expect "204"
  log "client mis a jour"
else
  api POST "/admin/realms/$REALM/clients" "$CLIENT_CONFIG"
  expect "201"
  api GET "/admin/realms/$REALM/clients?clientId=$API_CLIENT_ID"
  expect "200"
  CLIENT_UUID="$(jq -re '.[0].id' <<<"$RESP_BODY")"
  log "client cree"
fi

# Sans ce mapper, aud ne porte pas odyssai-api et l API rejette tout jeton.
api GET "/admin/realms/$REALM/clients/$CLIENT_UUID/protocol-mappers/models"
expect "200"
if ! jq -e 'any(.[]; .name == "odyssai-api-audience")' <<<"$RESP_BODY" >/dev/null; then
  api POST "/admin/realms/$REALM/clients/$CLIENT_UUID/protocol-mappers/models" \
    "$(jq -n --arg id "$API_CLIENT_ID" '{
      name: "odyssai-api-audience",
      protocol: "openid-connect",
      protocolMapper: "oidc-audience-mapper",
      config: {
        "included.client.audience": $id,
        "id.token.claim": "false",
        "access.token.claim": "true",
        "introspection.token.claim": "true"
      }
    }')"
  expect "201"
  log "mapper d audience cree"
else
  log "mapper d audience deja present"
fi

# --------------------------------------------------------------------- secrets

step "Configuration a reporter dans apps/api/.env"

api GET "/admin/realms/$REALM/clients/$CLIENT_UUID/client-secret"
expect "200"
CLIENT_SECRET="$(jq -re '.value' <<<"$RESP_BODY")"

cat <<EOF

KEYCLOAK_ISSUER=$KC_URL/realms/$REALM
KEYCLOAK_CLIENT_ID=$API_CLIENT_ID
KEYCLOAK_CLIENT_SECRET=$CLIENT_SECRET
API_BASE_URL=$API_BASE_URL
WEB_BASE_URL=$WEB_BASE_URL

EOF
