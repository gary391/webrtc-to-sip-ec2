#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/rtpengine/rtpengine.conf.template}
OUTPUT_FILE=${OUTPUT_FILE:-/etc/rtpengine/rtpengine.conf}

if [[ ${ALLOW_NON_ROOT:-false} != true && $EUID -ne 0 ]]; then
  printf 'ERROR: RTPEngine configuration must run as root.\n' >&2
  exit 1
fi

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

OUTPUT_MODE=0644 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$TEMPLATE_FILE" "$OUTPUT_FILE" \
  PRIVATE_IPV4 PUBLIC_IPV4 RTPENGINE_CONTROL_IP RTPENGINE_CONTROL_PORT \
  RTPENGINE_PORT_MIN RTPENGINE_PORT_MAX

grep -Fxq "listen-ng = 127.0.0.1:$RTPENGINE_CONTROL_PORT" "$OUTPUT_FILE" || {
  printf 'ERROR: rendered RTPEngine control socket is not loopback-only.\n' >&2
  exit 1
}
grep -Fxq 'table = -1' "$OUTPUT_FILE" || {
  printf 'ERROR: initial demo must use RTPEngine userspace forwarding.\n' >&2
  exit 1
}

if [[ ${SKIP_SYSTEMD:-false} != true ]]; then
  systemctl disable --now rtpengine-daemon >/dev/null 2>&1 || true
fi

printf 'Rendered RTPEngine configuration to %s; service remains disabled.\n' "$OUTPUT_FILE"
