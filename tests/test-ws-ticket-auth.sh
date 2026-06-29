#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

new_env() {
  local output=$1
  sed \
    -e 's/SIP_PASSWORD=change-me/SIP_PASSWORD=sip-secret-123456/' \
    -e 's/SIP_PEER_PASSWORD=change-me/SIP_PEER_PASSWORD=peer-secret-123456/' \
    -e 's/DB_ROOT_PASSWORD=change-me/DB_ROOT_PASSWORD=root-secret-123456/' \
    -e 's/DB_KAMAILIO_PASSWORD=change-me/DB_KAMAILIO_PASSWORD=db-secret-12345678/' \
    -e 's/TURN_PASSWORD=change-me/TURN_PASSWORD=turn-secret-123456/' \
    -e "s#WEB_CLIENT_ROOT=/var/www/webrtc-to-sip#WEB_CLIENT_ROOT=$TMP_DIR/www#" \
    -e "s#TLS_CERT_PATH=/etc/letsencrypt/live/sip.example.com/fullchain.pem#TLS_CERT_PATH=$TMP_DIR/fullchain.pem#" \
    -e "s#TLS_KEY_PATH=/etc/letsencrypt/live/sip.example.com/privkey.pem#TLS_KEY_PATH=$TMP_DIR/privkey.pem#" \
    "$ROOT_DIR/.env.example" > "$output"
}

assert_contains() {
  local file=$1
  local pattern=$2
  grep -Fq "$pattern" "$file" || {
    printf 'Expected %s to contain: %s\n' "$file" "$pattern" >&2
    exit 1
  }
}

assert_not_contains() {
  local file=$1
  local pattern=$2
  if grep -Fq "$pattern" "$file"; then
    printf 'Expected %s not to contain: %s\n' "$file" "$pattern" >&2
    exit 1
  fi
}

render_nginx() {
  local env_file=$1
  local output_file=$2
  ENV_FILE=$env_file OUTPUT_FILE=$output_file \
    TEMPLATE_FILE=$ROOT_DIR/templates/nginx/webrtc-to-sip.conf.template \
    ALLOW_NON_ROOT=true ALLOW_MISSING_TLS=true SKIP_NGINX_ENABLE=true \
    SKIP_NGINX_TEST=true SKIP_SYSTEMD=true \
    "$ROOT_DIR/deploy/native/configure-nginx.sh" >/dev/null
}

new_env "$TMP_DIR/disabled.env"
sed -i.bak \
  -e 's#WS_AUTH_SIDECAR_URL=http://127.0.0.1:9090/validate#WS_AUTH_SIDECAR_URL=#' \
  -e 's/WS_TICKET_QUERY_PARAM=ticket/WS_TICKET_QUERY_PARAM=/' \
  "$TMP_DIR/disabled.env"
ENV_FILE="$TMP_DIR/disabled.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
render_nginx "$TMP_DIR/disabled.env" "$TMP_DIR/disabled-nginx.conf"
assert_contains "$TMP_DIR/disabled-nginx.conf" 'location = /ws {'
assert_contains "$TMP_DIR/disabled-nginx.conf" 'proxy_pass http://127.0.0.1:8080;'
assert_not_contains "$TMP_DIR/disabled-nginx.conf" 'auth_request /ws-auth;'
assert_not_contains "$TMP_DIR/disabled-nginx.conf" 'location = /ws-auth'
assert_contains "$TMP_DIR/www/config.js" 'webSocketUri: "wss://sip.example.com/ws"'
assert_contains "$TMP_DIR/www/config.js" 'wsTicketAuthEnabled: false'

new_env "$TMP_DIR/enabled.env"
sed -i.bak \
  -e 's/ENABLE_WS_TICKET_AUTH=false/ENABLE_WS_TICKET_AUTH=true/' \
  -e 's#WS_AUTH_SIDECAR_URL=http://127.0.0.1:9090/validate#WS_AUTH_SIDECAR_URL=http://127.0.0.1:19090/validate#' \
  -e 's/WS_TICKET_QUERY_PARAM=ticket/WS_TICKET_QUERY_PARAM=ws_ticket/' \
  "$TMP_DIR/enabled.env"
ENV_FILE="$TMP_DIR/enabled.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
render_nginx "$TMP_DIR/enabled.env" "$TMP_DIR/enabled-nginx.conf"
assert_contains "$TMP_DIR/enabled-nginx.conf" 'auth_request /ws-auth;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'location = /ws-auth {'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'internal;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_pass http://127.0.0.1:19090/validate;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'if ($request_uri ~* "[?&]ws_ticket=([^&]+)") {'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_set_header X-WS-Ticket $ws_ticket;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_set_header Origin $http_origin;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_set_header X-Request-ID $request_id;'
assert_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_pass http://127.0.0.1:8080$uri;'
assert_not_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_pass http://127.0.0.1:8080$request_uri;'
assert_not_contains "$TMP_DIR/enabled-nginx.conf" 'proxy_pass http://127.0.0.1:19090/validate$request_uri;'
assert_contains "$TMP_DIR/www/config.js" 'wsTicketAuthEnabled: true'
assert_contains "$TMP_DIR/www/config.js" 'wsTicketQueryParam: "ws_ticket"'

new_env "$TMP_DIR/bad-bool.env"
sed -i.bak 's/ENABLE_WS_TICKET_AUTH=false/ENABLE_WS_TICKET_AUTH=maybe/' "$TMP_DIR/bad-bool.env"
if ENV_FILE="$TMP_DIR/bad-bool.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Invalid ENABLE_WS_TICKET_AUTH unexpectedly passed\n' >&2
  exit 1
fi

new_env "$TMP_DIR/bad-url.env"
sed -i.bak \
  -e 's/ENABLE_WS_TICKET_AUTH=false/ENABLE_WS_TICKET_AUTH=true/' \
  -e 's#WS_AUTH_SIDECAR_URL=http://127.0.0.1:9090/validate#WS_AUTH_SIDECAR_URL=https://validator.example.com/validate#' \
  "$TMP_DIR/bad-url.env"
if ENV_FILE="$TMP_DIR/bad-url.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Non-loopback WS_AUTH_SIDECAR_URL unexpectedly passed\n' >&2
  exit 1
fi

assert_contains "$ROOT_DIR/templates/client/app.js" 'window.setWebSocketTicket'
assert_contains "$ROOT_DIR/templates/client/app.js" 'searchParams.set(config.wsTicketQueryParam'
assert_not_contains "$ROOT_DIR/templates/client/app.js" 'localStorage'
assert_not_contains "$ROOT_DIR/templates/client/app.js" 'sessionStorage'

PYTHONDONTWRITEBYTECODE=1 python3 - "$ROOT_DIR" "$TMP_DIR/tickets.json" <<'PY'
import importlib.util
import pathlib
import sys
import time

root = pathlib.Path(sys.argv[1])
state_file = sys.argv[2]
module_path = root / "sidecar" / "ws_ticket_sidecar.py"
spec = importlib.util.spec_from_file_location("ws_ticket_sidecar", module_path)
sidecar = importlib.util.module_from_spec(spec)
sys.modules["ws_ticket_sidecar"] = sidecar
spec.loader.exec_module(sidecar)

ticket = sidecar.mint_ticket(state_file=state_file, ttl_seconds=60)
result = sidecar.validate_ticket(ticket, state_file=state_file)
assert result.ok and result.status == 204, result
result = sidecar.validate_ticket(ticket, state_file=state_file)
assert not result.ok and result.status == 403 and result.reason == "reused", result

expired = sidecar.mint_ticket(state_file=state_file, ttl_seconds=1)
time.sleep(2)
result = sidecar.validate_ticket(expired, state_file=state_file)
assert not result.ok and result.status == 401 and result.reason == "expired", result

wrong_scope = sidecar.mint_ticket(state_file=state_file, ttl_seconds=60, scope="other")
result = sidecar.validate_ticket(wrong_scope, state_file=state_file)
assert not result.ok and result.status == 403 and result.reason == "wrong-scope", result

assert sidecar.validate_ticket(None, state_file=state_file).reason == "missing"
assert sidecar.validate_ticket("not valid", state_file=state_file).reason == "malformed"
PY

printf 'WebSocket ticket auth tests passed.\n'
