#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
ACME_STAGING=${ACME_STAGING:-false}

[[ $EUID -eq 0 ]] || {
  printf 'ERROR: IP certificate renewal must run as root.\n' >&2
  exit 1
}

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

nginx_was_active=false
if systemctl is-active --quiet nginx; then
  nginx_was_active=true
fi

restore_nginx() {
  if [[ $nginx_was_active == true ]]; then
    systemctl start nginx || printf 'ERROR: failed to restore nginx.\n' >&2
  fi
}
trap restore_nginx EXIT

if [[ $nginx_was_active == true ]]; then
  systemctl stop nginx
fi

if ss -H -lnt 'sport = :80' | grep -q .; then
  printf 'ERROR: TCP port 80 is still in use; Certbot standalone cannot start.\n' >&2
  exit 1
fi

ENV_FILE=$ENV_FILE ACME_STAGING=$ACME_STAGING \
  "$ROOT_DIR/deploy/native/issue-ip-certificate.sh"

if [[ $nginx_was_active == true ]]; then
  nginx -t
  systemctl start nginx
  nginx_was_active=false
fi
trap - EXIT

if [[ $ACME_STAGING == false ]]; then
  openssl x509 -in "$TLS_CERT_PATH" -noout -subject -issuer -dates
fi

printf 'IP certificate renewal completed; nginx state restored.\n'
