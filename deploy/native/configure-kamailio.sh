#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/kamailio/kamailio.cfg.template}
OUTPUT_FILE=${OUTPUT_FILE:-/etc/kamailio/kamailio.cfg}
SYSTEMD_DROP_IN_SOURCE=${SYSTEMD_DROP_IN_SOURCE:-$ROOT_DIR/templates/systemd/kamailio.service.d/database.conf}
SYSTEMD_DROP_IN_FILE=${SYSTEMD_DROP_IN_FILE:-/etc/systemd/system/kamailio.service.d/database.conf}

if [[ ${ALLOW_NON_ROOT:-false} != true && $EUID -ne 0 ]]; then
  printf 'ERROR: Kamailio configuration must run as root.\n' >&2
  exit 1
fi

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

OUTPUT_MODE=0640 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$TEMPLATE_FILE" "$OUTPUT_FILE" \
  DOMAIN PRIVATE_IPV4 PUBLIC_IPV4 KAMAILIO_SIP_PORT KAMAILIO_WS_INTERNAL_PORT \
  DB_KAMAILIO_USER DB_KAMAILIO_PASSWORD DB_KAMAILIO_NAME \
  RTPENGINE_CONTROL_IP RTPENGINE_CONTROL_PORT

if [[ $EUID -eq 0 ]]; then
  chown root:kamailio "$OUTPUT_FILE"
fi

if command -v kamailio >/dev/null 2>&1; then
  kamailio -c -f "$OUTPUT_FILE"
fi

if [[ ${SKIP_SYSTEMD:-false} != true ]]; then
  install -D -m 0644 "$SYSTEMD_DROP_IN_SOURCE" "$SYSTEMD_DROP_IN_FILE"
  systemctl daemon-reload
  systemctl disable --now kamailio >/dev/null 2>&1 || true
fi

printf 'Rendered Kamailio configuration to %s; service remains disabled.\n' "$OUTPUT_FILE"
