#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in \
  deploy/native/configure.sh \
  deploy/native/install-certbot-ip.sh \
  deploy/native/issue-ip-certificate.sh \
  deploy/native/renew-ip-certificate.sh \
  deploy/native/start-services.sh \
  deploy/native/stop-services.sh \
  deploy/native/status.sh \
  deploy/debug/healthcheck.sh \
  deploy/debug/collect-debug.sh \
  deploy/debug/sip-trace.sh \
  deploy/debug/rtp-trace.sh \
  scripts/renew-ec2-ip-certificate.sh; do
  [[ -x $ROOT_DIR/$script ]] || {
    printf 'Operational script is not executable: %s\n' "$script" >&2
    exit 1
  }
done

grep -Fq 'systemctl enable --now mariadb' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fq 'systemctl enable --now rtpengine-daemon' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fq 'systemctl enable --now kamailio' "$ROOT_DIR/deploy/native/start-services.sh"
grep -Fxq 'Requires=mariadb.service' "$ROOT_DIR/templates/systemd/kamailio.service.d/database.conf"
grep -Fxq 'Requires=rtpengine-daemon.service' "$ROOT_DIR/templates/systemd/kamailio.service.d/database.conf"
grep -Fxq 'After=mariadb.service rtpengine-daemon.service' "$ROOT_DIR/templates/systemd/kamailio.service.d/database.conf"
grep -Fxq 'Wants=kamailio.service' "$ROOT_DIR/templates/systemd/nginx.service.d/kamailio.conf"
grep -Fxq 'After=kamailio.service' "$ROOT_DIR/templates/systemd/nginx.service.d/kamailio.conf"
grep -Fq 'systemctl daemon-reload' "$ROOT_DIR/deploy/native/configure-kamailio.sh"
grep -Fq 'systemctl daemon-reload' "$ROOT_DIR/deploy/native/configure-nginx.sh"
grep -Fq 'mysql://REDACTED:REDACTED@' "$ROOT_DIR/deploy/debug/collect-debug.sh"
grep -Fq 'coturn is inactive in the default mode' "$ROOT_DIR/deploy/debug/healthcheck.sh"
grep -Fq 'nginx:$ENABLE_NGINX' "$ROOT_DIR/deploy/native/status.sh"
grep -Fq 'if [[ $ENABLE_NGINX == true ]]; then' "$ROOT_DIR/deploy/debug/healthcheck.sh"
grep -Fq "'certbot>=5.4,<6'" "$ROOT_DIR/deploy/native/install-certbot-ip.sh"
grep -Fq 'systemctl disable --now certbot.timer' "$ROOT_DIR/deploy/native/install-certbot-ip.sh"
grep -Fq -- '--preferred-profile shortlived' "$ROOT_DIR/deploy/native/issue-ip-certificate.sh"
grep -Fq -- '--ip-address "$PUBLIC_IPV4"' "$ROOT_DIR/deploy/native/issue-ip-certificate.sh"
grep -Fq 'systemctl stop nginx' "$ROOT_DIR/deploy/native/renew-ip-certificate.sh"
grep -Fq 'trap restore_nginx EXIT' "$ROOT_DIR/deploy/native/renew-ip-certificate.sh"
grep -Fq 'ACME_STAGING=$ACME_STAGING' "$ROOT_DIR/deploy/native/renew-ip-certificate.sh"
grep -Fq 'authorize-security-group-ingress' "$ROOT_DIR/scripts/renew-ec2-ip-certificate.sh"
grep -Fq 'revoke-security-group-ingress' "$ROOT_DIR/scripts/renew-ec2-ip-certificate.sh"
grep -Fq 'trap revoke_rule EXIT' "$ROOT_DIR/scripts/renew-ec2-ip-certificate.sh"
grep -Fq 'sudo ACME_STAGING=true make renew-ip-certificate && sudo ACME_STAGING=false make renew-ip-certificate' \
  "$ROOT_DIR/scripts/renew-ec2-ip-certificate.sh"
grep -Fq 'public TCP/80 ingress already exists' "$ROOT_DIR/scripts/renew-ec2-ip-certificate.sh"

printf 'Operational tooling static tests passed.\n'
