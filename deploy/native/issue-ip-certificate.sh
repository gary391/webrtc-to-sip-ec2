#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
CERTBOT_IP=${CERTBOT_IP:-/usr/local/bin/certbot-ip}
ACME_STAGING=${ACME_STAGING:-true}

[[ $EUID -eq 0 ]] || {
  printf 'ERROR: IP certificate issuance must run as root.\n' >&2
  exit 1
}
ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ $ACME_STAGING == true || $ACME_STAGING == false ]] || {
  printf 'ERROR: ACME_STAGING must be true or false.\n' >&2
  exit 1
}
[[ -x $CERTBOT_IP ]] || {
  printf 'ERROR: install Certbot IP support first: sudo make install-certbot-ip\n' >&2
  exit 1
}
version=$($CERTBOT_IP --version | awk '{print $2}')
dpkg --compare-versions "$version" ge 5.4 || {
  printf 'ERROR: Certbot 5.4 or newer is required; found %s.\n' "$version" >&2
  exit 1
}

args=(
  certonly
  --non-interactive
  --agree-tos
  --preferred-profile shortlived
  --standalone
  --ip-address "$PUBLIC_IPV4"
  --cert-name "$PUBLIC_IPV4"
)
if [[ -n ${ACME_EMAIL:-} ]]; then
  args+=(--email "$ACME_EMAIL")
else
  args+=(--register-unsafely-without-email)
fi
if [[ $ACME_STAGING == true ]]; then
  args+=(
    --staging
    --config-dir /etc/letsencrypt-staging
    --work-dir /var/lib/letsencrypt-staging
    --logs-dir /var/log/letsencrypt-staging
  )
fi

"$CERTBOT_IP" "${args[@]}"

if [[ $ACME_STAGING == true ]]; then
  printf 'Staging IP certificate issued successfully; it is not browser-trusted.\n'
else
  printf 'Production IP certificate issued to /etc/letsencrypt/live/%s/.\n' "$PUBLIC_IPV4"
fi
