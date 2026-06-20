#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}

[[ $EUID -eq 0 ]] || { printf 'ERROR: starting services requires root.\n' >&2; exit 1; }
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required_files=(
  /etc/mysql/mariadb.conf.d/60-webrtc-to-sip.cnf
  /etc/rtpengine/rtpengine.conf
  /etc/kamailio/kamailio.cfg
)
if [[ $ENABLE_NGINX == true ]]; then
  required_files+=(/etc/nginx/sites-available/webrtc-to-sip.conf "$TLS_CERT_PATH" "$TLS_KEY_PATH")
fi
for file in "${required_files[@]}"; do
  [[ -r $file ]] || { printf 'ERROR: required configuration is missing: %s\n' "$file" >&2; exit 1; }
done

kamailio -c -f /etc/kamailio/kamailio.cfg
if [[ $ENABLE_NGINX == true ]]; then nginx -t; fi

systemctl enable --now mariadb
systemctl enable --now rtpengine-daemon
systemctl enable --now kamailio
if [[ $ENABLE_NGINX == true ]]; then systemctl enable --now nginx; fi
if [[ $ENABLE_TURN == true ]]; then systemctl enable --now coturn; fi

printf 'Native services started in dependency order.\n'
