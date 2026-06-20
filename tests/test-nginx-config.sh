#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

sed \
  -e 's/SIP_PASSWORD=change-me/SIP_PASSWORD=sip-secret-123456/' \
  -e 's/DB_ROOT_PASSWORD=change-me/DB_ROOT_PASSWORD=root-secret-123456/' \
  -e 's/DB_KAMAILIO_PASSWORD=change-me/DB_KAMAILIO_PASSWORD=db-secret-12345678/' \
  -e 's/TURN_PASSWORD=change-me/TURN_PASSWORD=turn-secret-123456/' \
  -e "s#WEB_CLIENT_ROOT=/var/www/webrtc-to-sip#WEB_CLIENT_ROOT=$TMP_DIR/www#" \
  -e "s#TLS_CERT_PATH=/etc/letsencrypt/live/sip.example.com/fullchain.pem#TLS_CERT_PATH=$TMP_DIR/fullchain.pem#" \
  -e "s#TLS_KEY_PATH=/etc/letsencrypt/live/sip.example.com/privkey.pem#TLS_KEY_PATH=$TMP_DIR/privkey.pem#" \
  "$ROOT_DIR/.env.example" > "$TMP_DIR/test.env"

ENV_FILE=$TMP_DIR/test.env OUTPUT_FILE=$TMP_DIR/nginx.conf \
  ALLOW_NON_ROOT=true ALLOW_MISSING_TLS=true SKIP_NGINX_ENABLE=true \
  SKIP_NGINX_TEST=true SKIP_SYSTEMD=true \
  "$ROOT_DIR/deploy/native/configure-nginx.sh" >/dev/null

for expected in \
  'listen 443 ssl;' \
  'ssl_protocols TLSv1.2 TLSv1.3;' \
  'location = /ws {' \
  'proxy_pass http://127.0.0.1:8080;' \
  'proxy_set_header Upgrade $http_upgrade;' \
  'proxy_buffering off;'; do
  grep -Fq "$expected" "$TMP_DIR/nginx.conf" || {
    printf 'Nginx configuration is missing: %s\n' "$expected" >&2
    exit 1
  }
done

[[ -f $TMP_DIR/www/index.html ]]
grep -Fq 'stun:stun.l.google.com:19302' "$TMP_DIR/www/config.js"
if grep -Eq 'TLSv1(\.0|\.1)?[ ;]' "$TMP_DIR/nginx.conf"; then
  printf 'Nginx configuration enables obsolete TLS\n' >&2
  exit 1
fi

printf 'Nginx configuration rendering tests passed.\n'
