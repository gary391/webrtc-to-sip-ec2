#!/usr/bin/env bash
set -euo pipefail

failed=false
for service in mariadb rtpengine-daemon kamailio nginx; do
  if systemctl is-active --quiet "$service"; then
    printf '%-20s active\n' "$service"
  else
    printf '%-20s inactive\n' "$service"
    failed=true
  fi
done

if systemctl is-active --quiet coturn; then
  printf '%-20s active (optional)\n' coturn
else
  printf '%-20s inactive (expected unless TURN is enabled)\n' coturn
fi

ss -lntup
[[ $failed == false ]]
