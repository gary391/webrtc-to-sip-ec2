#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { printf 'ERROR: stopping services requires root.\n' >&2; exit 1; }
for service in coturn nginx kamailio rtpengine-daemon mariadb; do
  systemctl disable --now "$service" >/dev/null 2>&1 || true
done
printf 'Native services stopped and disabled.\n'
