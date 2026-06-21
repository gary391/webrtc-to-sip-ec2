#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

sed \
  -e 's/SIP_PASSWORD=change-me/SIP_PASSWORD=sip-secret-123456/' \
  -e 's/SIP_PEER_PASSWORD=change-me/SIP_PEER_PASSWORD=peer-secret-123456/' \
  -e 's/DB_ROOT_PASSWORD=change-me/DB_ROOT_PASSWORD=root-secret-123456/' \
  -e 's/DB_KAMAILIO_PASSWORD=change-me/DB_KAMAILIO_PASSWORD=db-secret-12345678/' \
  -e 's/TURN_PASSWORD=change-me/TURN_PASSWORD=turn-secret-123456/' \
  -e "s#WEB_CLIENT_ROOT=/var/www/webrtc-to-sip#WEB_CLIENT_ROOT=$TMP_DIR/www#" \
  -e "s#TLS_CERT_PATH=/etc/letsencrypt/live/sip.example.com/fullchain.pem#TLS_CERT_PATH=$TMP_DIR/fullchain.pem#" \
  -e "s#TLS_KEY_PATH=/etc/letsencrypt/live/sip.example.com/privkey.pem#TLS_KEY_PATH=$TMP_DIR/privkey.pem#" \
  "$ROOT_DIR/.env.example" > "$TMP_DIR/test.env"

ENV_FILE=$TMP_DIR/test.env OUTPUT_FILE=$TMP_DIR/nginx.conf \
  TEMPLATE_FILE=$ROOT_DIR/templates/nginx/webrtc-to-sip.conf.template \
  ALLOW_NON_ROOT=true ALLOW_MISSING_TLS=true SKIP_NGINX_ENABLE=true \
  SKIP_NGINX_TEST=true SKIP_SYSTEMD=true \
  "$ROOT_DIR/deploy/native/configure-nginx.sh" >/dev/null

for expected in \
  'listen 443 ssl;' \
  'ssl_protocols TLSv1.2 TLSv1.3;' \
  'add_header Permissions-Policy "microphone=(self)" always;' \
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
[[ -f $TMP_DIR/www/app.js ]]
[[ -f $TMP_DIR/www/styles.css ]]
[[ -f $TMP_DIR/www/vendor/jssip-3.13.8.min.js ]]
[[ -f $TMP_DIR/www/vendor/JSSIP-LICENSE.md ]]
grep -Fq '<audio id="remote-audio" autoplay controls playsinline>' "$TMP_DIR/www/index.html"
grep -Fq '#remote-audio { width: 100%; margin-top: 18px; }' "$TMP_DIR/www/styles.css"
grep -Fq 'stun:stun.l.google.com:19302' "$TMP_DIR/www/config.js"
grep -Fq 'wss://sip.example.com/ws' "$TMP_DIR/www/config.js"
grep -Fq 'new JsSIP.WebSocketInterface' "$TMP_DIR/www/app.js"
grep -Fq 'navigator.mediaDevices.getUserMedia' "$TMP_DIR/www/app.js"
grep -Fq "Microphone blocked. Allow microphone access" "$TMP_DIR/www/app.js"
grep -Fq "elements.hangup.addEventListener('click', terminateActiveSession)" "$TMP_DIR/www/app.js"
grep -Fq "appendLog('Ending call')" "$TMP_DIR/www/app.js"
grep -Fq 'Remote audio is ready; press Play' "$TMP_DIR/www/app.js"
grep -Fq 'event.streams[0] || new MediaStream([event.track])' "$TMP_DIR/www/app.js"
grep -Fq 'Remote audio playback started' "$TMP_DIR/www/app.js"
if grep -Eq 'TLSv1(\.0|\.1)?[ ;]' "$TMP_DIR/nginx.conf"; then
  printf 'Nginx configuration enables obsolete TLS\n' >&2
  exit 1
fi

printf 'Nginx configuration rendering tests passed.\n'
