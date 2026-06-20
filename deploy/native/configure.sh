#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}

[[ $EUID -eq 0 ]] || { printf 'ERROR: native configuration must run as root.\n' >&2; exit 1; }
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/configure-mariadb.sh"
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/configure-rtpengine.sh"
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/configure-kamailio.sh"
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/configure-nginx.sh"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
if [[ $ENABLE_TURN == true ]]; then
  [[ -x $ROOT_DIR/deploy/native/configure-coturn.sh ]] || {
    printf 'ERROR: TURN was requested but optional coturn configuration is not implemented.\n' >&2
    exit 1
  }
  ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/configure-coturn.sh"
fi

printf 'Native configuration completed. Run make native-start after reviewing generated files.\n'
