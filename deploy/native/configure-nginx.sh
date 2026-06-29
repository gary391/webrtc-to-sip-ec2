#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/nginx/webrtc-to-sip.conf.template}
OUTPUT_FILE=${OUTPUT_FILE:-/etc/nginx/sites-available/webrtc-to-sip.conf}
ENABLED_FILE=${ENABLED_FILE:-/etc/nginx/sites-enabled/webrtc-to-sip.conf}
SYSTEMD_DROP_IN_SOURCE=${SYSTEMD_DROP_IN_SOURCE:-$ROOT_DIR/templates/systemd/nginx.service.d/kamailio.conf}
SYSTEMD_DROP_IN_FILE=${SYSTEMD_DROP_IN_FILE:-/etc/systemd/system/nginx.service.d/kamailio.conf}

if [[ ${ALLOW_NON_ROOT:-false} != true && $EUID -ne 0 ]]; then
  printf 'ERROR: Nginx configuration must run as root.\n' >&2
  exit 1
fi

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ $ENABLE_NGINX == true ]] || {
  printf 'Nginx is disabled by ENABLE_NGINX=false.\n'
  exit 0
}

if [[ ${ALLOW_MISSING_TLS:-false} != true ]]; then
  [[ -r $TLS_CERT_PATH ]] || { printf 'ERROR: TLS certificate is not readable: %s\n' "$TLS_CERT_PATH" >&2; exit 1; }
  [[ -r $TLS_KEY_PATH ]] || { printf 'ERROR: TLS key is not readable: %s\n' "$TLS_KEY_PATH" >&2; exit 1; }
fi

WS_TICKET_AUTH_NGINX_BLOCK="        # WebSocket ticket auth disabled"
WS_AUTH_LOCATION_NGINX_BLOCK="    # WebSocket ticket auth disabled"
WS_KAMAILIO_PROXY_PASS="http://127.0.0.1:${KAMAILIO_WS_INTERNAL_PORT}"
if [[ $ENABLE_WS_TICKET_AUTH == true ]]; then
  WS_TICKET_AUTH_NGINX_BLOCK="        auth_request /ws-auth;"
  WS_KAMAILIO_PROXY_PASS="http://127.0.0.1:${KAMAILIO_WS_INTERNAL_PORT}\$uri"
  WS_AUTH_LOCATION_NGINX_BLOCK=$(cat <<EOF

    location = /ws-auth {
        internal;
        set \$ws_ticket "";
        if (\$request_uri ~* "[?&]${WS_TICKET_QUERY_PARAM}=([^&]+)") {
            set \$ws_ticket \$1;
        }
        proxy_pass ${WS_AUTH_SIDECAR_URL};
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-WS-Ticket \$ws_ticket;
        proxy_set_header Origin \$http_origin;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Request-ID \$request_id;
    }
EOF
)
fi
export WS_TICKET_AUTH_NGINX_BLOCK WS_AUTH_LOCATION_NGINX_BLOCK WS_KAMAILIO_PROXY_PASS

install -d -m 0755 "$WEB_CLIENT_ROOT"
install -m 0644 "$ROOT_DIR/templates/client/index.html" "$WEB_CLIENT_ROOT/index.html"
install -m 0644 "$ROOT_DIR/templates/client/app.js" "$WEB_CLIENT_ROOT/app.js"
install -m 0644 "$ROOT_DIR/templates/client/styles.css" "$WEB_CLIENT_ROOT/styles.css"
install -d -m 0755 "$WEB_CLIENT_ROOT/vendor"
install -m 0644 "$ROOT_DIR/templates/client/vendor/jssip-3.13.8.min.js" \
  "$WEB_CLIENT_ROOT/vendor/jssip-3.13.8.min.js"
install -m 0644 "$ROOT_DIR/templates/client/vendor/JSSIP-LICENSE.md" \
  "$WEB_CLIENT_ROOT/vendor/JSSIP-LICENSE.md"
TEMPLATE_FILE=$ROOT_DIR/templates/client/config.js.template \
  OUTPUT_FILE=$WEB_CLIENT_ROOT/config.js ENV_FILE=$ENV_FILE \
  "$ROOT_DIR/deploy/native/render-client-config.sh" >/dev/null

OUTPUT_MODE=0644 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$TEMPLATE_FILE" "$OUTPUT_FILE" DOMAIN WEB_CLIENT_ROOT TLS_CERT_PATH \
  TLS_KEY_PATH KAMAILIO_WS_INTERNAL_PORT WS_TICKET_AUTH_NGINX_BLOCK \
  WS_AUTH_LOCATION_NGINX_BLOCK WS_KAMAILIO_PROXY_PASS

if [[ ${SKIP_NGINX_ENABLE:-false} != true ]]; then
  ln -sfn "$OUTPUT_FILE" "$ENABLED_FILE"
fi
if command -v nginx >/dev/null 2>&1 && [[ ${SKIP_NGINX_TEST:-false} != true ]]; then
  nginx -t
fi
if [[ ${SKIP_SYSTEMD:-false} != true ]]; then
  install -D -m 0644 "$SYSTEMD_DROP_IN_SOURCE" "$SYSTEMD_DROP_IN_FILE"
  systemctl daemon-reload
  systemctl disable --now nginx >/dev/null 2>&1 || true
fi

printf 'Rendered Nginx configuration to %s; service remains disabled.\n' "$OUTPUT_FILE"
