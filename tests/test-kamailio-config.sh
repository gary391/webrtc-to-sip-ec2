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
  "$ROOT_DIR/.env.example" > "$TMP_DIR/test.env"

ENV_FILE=$TMP_DIR/test.env OUTPUT_FILE=$TMP_DIR/kamailio.cfg \
  ALLOW_NON_ROOT=true SKIP_SYSTEMD=true \
  "$ROOT_DIR/deploy/native/configure-kamailio.sh" >/dev/null

for expected in \
  'alias="sip.example.com"' \
  'listen=udp:10.0.1.25:5060 advertise 203.0.113.10:5060' \
  'listen=tcp:10.0.1.25:5060 advertise 203.0.113.10:5060' \
  'listen=tcp:127.0.0.1:8080' \
  'modparam("rr", "enable_double_rr", 1)' \
  'udp:127.0.0.1:22222' \
  'auth_check("$fd", "subscriber", "1")' \
  'send_reply("403", "Not relaying")' \
  'FLB_FROM_WEBRTC' \
  'FLB_TO_WEBRTC' \
  '$avp(MEDIA_DIRECTION) = "from-webrtc"' \
  '$avp(MEDIA_DIRECTION) = "to-webrtc"' \
  '$avp(MEDIA_DIRECTION) == "from-webrtc"' \
  '$avp(MEDIA_DIRECTION) == "to-webrtc"' \
  'if ($proto =~ "ws")' \
  'if ($rU != $null && uri == myself)' \
  'DTLS=off SDES-off ICE=remove RTP/AVP' \
  'DTLS=passive SDES-off ICE=force RTP/SAVPF' \
  'ws_handle_handshake()'; do
  grep -Fq "$expected" "$TMP_DIR/kamailio.cfg" || {
    printf 'Kamailio configuration is missing: %s\n' "$expected" >&2
    exit 1
  }
done

if stat --version >/dev/null 2>&1; then
  output_mode=$(stat -c '%a' "$TMP_DIR/kamailio.cfg")
else
  output_mode=$(stat -f '%Lp' "$TMP_DIR/kamailio.cfg")
fi
[[ $output_mode == 640 ]]
if grep -Eq '{{[A-Z][A-Z0-9_]*}}' "$TMP_DIR/kamailio.cfg"; then
  printf 'Kamailio configuration contains unresolved placeholders\n' >&2
  exit 1
fi

printf 'Kamailio configuration rendering tests passed.\n'
