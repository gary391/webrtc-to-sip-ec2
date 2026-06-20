#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in \
  deploy/native/configure.sh \
  deploy/native/install-certbot-ip.sh \
  deploy/native/issue-ip-certificate.sh \
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
grep -Fq 'nginx:$ENABLE_NGINX' "$ROOT_DIR/deploy/native/status.sh"
grep -Fq 'if [[ $ENABLE_NGINX == true ]]; then' "$ROOT_DIR/deploy/debug/healthcheck.sh"
grep -Fq "'certbot>=5.4,<6'" "$ROOT_DIR/deploy/native/install-certbot-ip.sh"
grep -Fq 'systemctl disable --now certbot.timer' "$ROOT_DIR/deploy/native/install-certbot-ip.sh"
grep -Fq -- '--preferred-profile shortlived' "$ROOT_DIR/deploy/native/issue-ip-certificate.sh"
grep -Fq -- '--ip-address "$PUBLIC_IPV4"' "$ROOT_DIR/deploy/native/issue-ip-certificate.sh"

printf 'Operational tooling static tests passed.\n'
