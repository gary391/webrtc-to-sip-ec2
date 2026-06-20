#!/usr/bin/env bash
set -euo pipefail

VENV_DIR=${CERTBOT_IP_VENV_DIR:-/opt/certbot-ip}
LINK_PATH=${CERTBOT_IP_LINK_PATH:-/usr/local/bin/certbot-ip}

[[ $EUID -eq 0 ]] || {
  printf 'ERROR: Certbot IP support installation must run as root.\n' >&2
  exit 1
}

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade pip
"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check \
  --upgrade 'certbot>=5.4,<6'
ln -sfn "$VENV_DIR/bin/certbot" "$LINK_PATH"

version=$($LINK_PATH --version | awk '{print $2}')
dpkg --compare-versions "$version" ge 5.4 || {
  printf 'ERROR: Certbot 5.4 or newer is required; installed %s.\n' "$version" >&2
  exit 1
}

printf 'Installed isolated IP-certificate client: %s\n' "$($LINK_PATH --version)"
