#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

failures=0
check() {
  local description=$1
  shift
  if "$@"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description" >&2
    failures=$((failures + 1))
  fi
}

for service in mariadb rtpengine-daemon kamailio; do
  check "$service is active" systemctl is-active --quiet "$service"
done
if [[ $ENABLE_NGINX == true ]]; then
  check 'nginx is active' systemctl is-active --quiet nginx
fi
if [[ $ENABLE_TURN == false ]]; then
  check 'coturn is inactive in the default mode' bash -c '! systemctl is-active --quiet coturn'
fi

listeners=$(ss -lntupH)
if [[ $ENABLE_NGINX == true ]]; then
  check 'HTTPS listens on TCP 443' grep -Eq 'LISTEN.*:443([[:space:]]|$)' <<< "$listeners"
fi
check 'Kamailio SIP listens on port 5060' grep -Eq '(:5060[[:space:]])' <<< "$listeners"
check 'RTPEngine control is loopback-only' grep -Eq '127\.0\.0\.1:22222([[:space:]]|$)' <<< "$listeners"
check 'MariaDB is not publicly bound' bash -c '! grep -Eq "(0\\.0\\.0\\.0|\\[::\\]):3306" <<< "$1"' _ "$listeners"

if [[ $ENABLE_NGINX == true ]]; then
  check 'HTTPS serves the client root' curl --fail --silent --show-error --max-time 5 \
    --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" --output /dev/null
fi

if (( failures > 0 )); then
  printf 'Health check failed: %d check(s).\n' "$failures" >&2
  exit 1
fi
printf 'Health check passed.\n'
