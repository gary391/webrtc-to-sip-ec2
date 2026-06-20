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
  "$ROOT_DIR/.env.example" > "$TMP_DIR/test.env"

ENV_FILE=$TMP_DIR/test.env OUTPUT_FILE=$TMP_DIR/kamailio.cfg \
  ALLOW_NON_ROOT=true SKIP_SYSTEMD=true \
  "$ROOT_DIR/deploy/native/configure-kamailio.sh" >/dev/null

for expected in \
  'alias="sip.example.com"' \
  'listen=udp:10.0.1.25:5060' \
  'listen=tcp:127.0.0.1:8080' \
  'udp:127.0.0.1:22222' \
  'auth_check("$fd", "subscriber", "1")' \
  'send_reply("403", "Not relaying")' \
  'FLB_FROM_WEBRTC' \
  'FLB_TO_WEBRTC' \
  'DTLS=off SDES-off ICE=remove RTP/AVP' \
  'DTLS=passive SDES-off ICE=force RTP/SAVPF' \
  'ws_handle_handshake()'; do
  grep -Fq "$expected" "$TMP_DIR/kamailio.cfg" || {
    printf 'Kamailio configuration is missing: %s\n' "$expected" >&2
    exit 1
  }
done

[[ $(stat -f '%Lp' "$TMP_DIR/kamailio.cfg" 2>/dev/null || stat -c '%a' "$TMP_DIR/kamailio.cfg") == 600 ]]
if grep -Eq '{{[A-Z][A-Z0-9_]*}}' "$TMP_DIR/kamailio.cfg"; then
  printf 'Kamailio configuration contains unresolved placeholders\n' >&2
  exit 1
fi

printf 'Kamailio configuration rendering tests passed.\n'
