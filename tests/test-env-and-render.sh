#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

new_env() {
  local mode=$1
  local enable_turn=$2
  sed \
    -e 's/SIP_PASSWORD=change-me/SIP_PASSWORD=sip-secret-123456/' \
    -e 's/SIP_PEER_PASSWORD=change-me/SIP_PEER_PASSWORD=peer-secret-123456/' \
    -e 's/DB_ROOT_PASSWORD=change-me/DB_ROOT_PASSWORD=root-secret-123456/' \
    -e 's/DB_KAMAILIO_PASSWORD=change-me/DB_KAMAILIO_PASSWORD=db-secret-12345678/' \
    -e 's/TURN_PASSWORD=change-me/TURN_PASSWORD=turn-secret-123456/' \
    -e "s/ICE_MODE=stun/ICE_MODE=$mode/" \
    -e "s/ENABLE_TURN=false/ENABLE_TURN=$enable_turn/" \
    "$ROOT_DIR/.env.example" > "$TMP_DIR/$mode.env"
}

assert_contains() {
  local file=$1
  local pattern=$2
  grep -Fq "$pattern" "$file" || {
    printf 'Expected %s to contain: %s\n' "$file" "$pattern" >&2
    exit 1
  }
}

new_env stun false
ENV_FILE="$TMP_DIR/stun.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
ENV_FILE="$TMP_DIR/stun.env" OUTPUT_FILE="$TMP_DIR/stun.js" \
  "$ROOT_DIR/deploy/native/render-client-config.sh" >/dev/null
assert_contains "$TMP_DIR/stun.js" 'stun:stun.l.google.com:19302'
assert_contains "$TMP_DIR/stun.js" 'wss://sip.example.com/ws'
assert_contains "$TMP_DIR/stun.js" 'defaultSipUser: "websip"'
assert_contains "$TMP_DIR/stun.js" 'defaultPeerUser: "softphone"'
if grep -Fq 'turn:' "$TMP_DIR/stun.js"; then
  printf 'STUN mode unexpectedly rendered TURN entries\n' >&2
  exit 1
fi

new_env none false
ENV_FILE="$TMP_DIR/none.env" OUTPUT_FILE="$TMP_DIR/none.js" \
  "$ROOT_DIR/deploy/native/render-client-config.sh" >/dev/null
assert_contains "$TMP_DIR/none.js" 'iceServers: []'

new_env turn true
ENV_FILE="$TMP_DIR/turn.env" OUTPUT_FILE="$TMP_DIR/turn.js" \
  "$ROOT_DIR/deploy/native/render-client-config.sh" >/dev/null
assert_contains "$TMP_DIR/turn.js" 'turn:sip.example.com:3478?transport=udp'
assert_contains "$TMP_DIR/turn.js" 'turn:sip.example.com:3478?transport=tcp'

new_env turn false
if ENV_FILE="$TMP_DIR/turn.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'TURN mode without ENABLE_TURN=true unexpectedly passed\n' >&2
  exit 1
fi

new_env stun false
sed -i.bak 's#ADMIN_CIDR=198.51.100.25/32#ADMIN_CIDR=0.0.0.0/0#' "$TMP_DIR/stun.env"
if ENV_FILE="$TMP_DIR/stun.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Broad ADMIN_CIDR unexpectedly passed\n' >&2
  exit 1
fi

new_env stun false
sed -i.bak \
  -e 's/RTPENGINE_PORT_MIN=30000/RTPENGINE_PORT_MIN=30039/' \
  -e 's/RTPENGINE_PORT_MAX=30039/RTPENGINE_PORT_MAX=30000/' \
  "$TMP_DIR/stun.env"
if ENV_FILE="$TMP_DIR/stun.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Reversed RTPEngine port range unexpectedly passed\n' >&2
  exit 1
fi

if ENV_FILE="$ROOT_DIR/.env.example" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Placeholder secrets unexpectedly passed\n' >&2
  exit 1
fi

new_env stun false
sed -i.bak 's/DEBIAN_CODENAME=trixie/DEBIAN_CODENAME=bookworm/' "$TMP_DIR/stun.env"
if ENV_FILE="$TMP_DIR/stun.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Unreviewed Debian release unexpectedly passed\n' >&2
  exit 1
fi

new_env stun false
sed -i.bak 's/RTPENGINE_SERIES=13.5/RTPENGINE_SERIES=12.5/' "$TMP_DIR/stun.env"
if ENV_FILE="$TMP_DIR/stun.env" "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null 2>&1; then
  printf 'Unreviewed RTPEngine release series unexpectedly passed\n' >&2
  exit 1
fi

printf 'Environment and ICE rendering tests passed.\n'
