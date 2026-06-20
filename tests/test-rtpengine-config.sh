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

ENV_FILE=$TMP_DIR/test.env OUTPUT_FILE=$TMP_DIR/rtpengine.conf \
  ALLOW_NON_ROOT=true SKIP_SYSTEMD=true \
  "$ROOT_DIR/deploy/native/configure-rtpengine.sh" >/dev/null

grep -Fxq 'table = -1' "$TMP_DIR/rtpengine.conf"
grep -Fxq 'interface = 10.0.1.25!203.0.113.10' "$TMP_DIR/rtpengine.conf"
grep -Fxq 'listen-ng = 127.0.0.1:22222' "$TMP_DIR/rtpengine.conf"
grep -Fxq 'port-min = 30000' "$TMP_DIR/rtpengine.conf"
grep -Fxq 'port-max = 30039' "$TMP_DIR/rtpengine.conf"
if grep -Eq '{{[A-Z][A-Z0-9_]*}}' "$TMP_DIR/rtpengine.conf"; then
  printf 'Rendered RTPEngine configuration contains unresolved placeholders\n' >&2
  exit 1
fi

printf 'RTPEngine configuration tests passed.\n'
