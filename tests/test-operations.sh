#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in \
  deploy/native/configure.sh \
  deploy/native/start-services.sh \
  deploy/native/stop-services.sh \
  deploy/native/status.sh \
  deploy/debug/healthcheck.sh \
  deploy/debug/collect-debug.sh \
  deploy/debug/sip-trace.sh \
  deploy/debug/rtp-trace.sh; do
  [[ -x $ROOT_DIR/$script ]] || {
    printf 'Operational script is not executable: %s\n' "$script" >&2
    exit 1
  }
done

grep -Fq 'systemctl enable --now mariadb' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fq 'systemctl enable --now rtpengine-daemon' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fq 'systemctl enable --now kamailio' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fq 'mysql://REDACTED:REDACTED@' "$ROOT_DIR/deploy/debug/collect-debug.sh"
grep -Fq 'coturn is inactive in the default mode' "$ROOT_DIR/deploy/debug/healthcheck.sh"

printf 'Operational tooling static tests passed.\n'
