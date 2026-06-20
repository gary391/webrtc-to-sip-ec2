#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/nginx/webrtc-to-sip.conf.template}
OUTPUT_FILE=${OUTPUT_FILE:-/etc/nginx/sites-available/webrtc-to-sip.conf}
ENABLED_FILE=${ENABLED_FILE:-/etc/nginx/sites-enabled/webrtc-to-sip.conf}

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

install -d -m 0755 "$WEB_CLIENT_ROOT"
install -m 0644 "$ROOT_DIR/templates/client/index.html" "$WEB_CLIENT_ROOT/index.html"
OUTPUT_FILE=$WEB_CLIENT_ROOT/config.js ENV_FILE=$ENV_FILE \
  "$ROOT_DIR/deploy/native/render-client-config.sh" >/dev/null

OUTPUT_MODE=0644 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$TEMPLATE_FILE" "$OUTPUT_FILE" DOMAIN WEB_CLIENT_ROOT TLS_CERT_PATH \
  TLS_KEY_PATH KAMAILIO_WS_INTERNAL_PORT

if [[ ${SKIP_NGINX_ENABLE:-false} != true ]]; then
  ln -sfn "$OUTPUT_FILE" "$ENABLED_FILE"
fi
if command -v nginx >/dev/null 2>&1 && [[ ${SKIP_NGINX_TEST:-false} != true ]]; then
  nginx -t
fi
if [[ ${SKIP_SYSTEMD:-false} != true ]]; then
  systemctl disable --now nginx >/dev/null 2>&1 || true
fi

printf 'Rendered Nginx configuration to %s; service remains disabled.\n' "$OUTPUT_FILE"
