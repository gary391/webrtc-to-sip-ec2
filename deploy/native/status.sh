#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

failed=false
for service in mariadb rtpengine-daemon kamailio; do
  if systemctl is-active --quiet "$service"; then
    printf '%-20s active\n' "$service"
  else
    printf '%-20s inactive\n' "$service"
    failed=true
  fi
done

for service_and_flag in "nginx:$ENABLE_NGINX" "coturn:$ENABLE_TURN"; do
  service=${service_and_flag%%:*}
  enabled=${service_and_flag##*:}
  if systemctl is-active --quiet "$service"; then
    printf '%-20s active\n' "$service"
    [[ $enabled == true ]] || failed=true
  else
    printf '%-20s inactive%s\n' "$service" "$([[ $enabled == false ]] && printf ' (expected)')"
    [[ $enabled == false ]] || failed=true
  fi
done

ss -lntup
[[ $failed == false ]]
