#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
VERSION_FILE=${VERSION_FILE:-/opt/webrtc-to-sip/installed-versions.txt}

[[ $EUID -eq 0 ]] || {
  printf 'ERROR: native installation must run as root.\n' >&2
  exit 1
}

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 && ${VERSION_CODENAME:-} == trixie ]] || {
  printf 'ERROR: this installer requires Debian 13 Trixie.\n' >&2
  exit 1
}
[[ $(dpkg --print-architecture) == amd64 ]] || {
  printf 'ERROR: this installer currently requires amd64.\n' >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
policy_created=false
work_dir=$(mktemp -d)

cleanup() {
  rm -rf "$work_dir"
  if [[ $policy_created == true ]]; then
    rm -f /usr/sbin/policy-rc.d
  fi
}
trap cleanup EXIT

# Prevent packages from starting network services before configuration is rendered.
if [[ ! -e /usr/sbin/policy-rc.d ]]; then
  printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
  chmod 0755 /usr/sbin/policy-rc.d
  policy_created=true
fi

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates certbot curl dnsutils git gnupg iproute2 jq lsb-release make \
  mariadb-server net-tools ngrep nginx python3 python3-venv sngrep tcpdump tmux \
  unzip vim

kamailio_key=$work_dir/kamailio-key.gpg
curl --fail --silent --show-error --location --retry 3 \
  https://deb.kamailio.org/kamailiodebkey.gpg |
  gpg --batch --yes --dearmor --output "$kamailio_key"
install -m 0644 "$kamailio_key" /usr/share/keyrings/kamailio.gpg
printf 'deb [signed-by=/usr/share/keyrings/kamailio.gpg] %s %s main\n' \
  "$KAMAILIO_APT_REPOSITORY" "$DEBIAN_CODENAME" \
  > /etc/apt/sources.list.d/kamailio.list

apt-get update
apt-get install -y --no-install-recommends \
  kamailio kamailio-extra-modules kamailio-mysql-modules \
  kamailio-tls-modules kamailio-websocket-modules

release_record=$(
  ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/native/resolve-rtpengine-release.sh"
)
IFS=$'\t' read -r rtpengine_tag asset_name asset_url asset_sha256 <<< "$release_record"
[[ -n $rtpengine_tag && -n $asset_name && -n $asset_url && -n $asset_sha256 ]] || {
  printf 'ERROR: RTPEngine release resolver returned an incomplete record.\n' >&2
  exit 1
}

rtpengine_deb=$work_dir/$asset_name
curl --fail --silent --show-error --location --retry 3 "$asset_url" --output "$rtpengine_deb"
printf '%s  %s\n' "$asset_sha256" "$rtpengine_deb" | sha256sum --check --status || {
  printf 'ERROR: RTPEngine package SHA-256 verification failed.\n' >&2
  exit 1
}
apt-get install -y "$rtpengine_deb"

if [[ $ENABLE_TURN == true ]]; then
  apt-get install -y --no-install-recommends coturn
fi

for service in kamailio rtpengine-daemon nginx mariadb coturn; do
  systemctl disable --now "$service" >/dev/null 2>&1 || true
done

install -d -m 0755 "$(dirname "$VERSION_FILE")"
{
  printf 'Installed at: %s\n' "$(date --iso-8601=seconds)"
  printf 'Debian: %s (%s)\n' "$PRETTY_NAME" "$VERSION_CODENAME"
  printf 'Kamailio:\n'
  kamailio -V
  printf 'RTPEngine release: %s\n' "$rtpengine_tag"
  printf 'RTPEngine package: %s\n' "$(dpkg-query -W -f='${Version}' rtpengine-daemon)"
  rtpengine --version
} > "$VERSION_FILE"
chmod 0644 "$VERSION_FILE"

printf 'Native packages installed. Services remain disabled until configuration completes.\n'
printf 'Installed versions: %s\n' "$VERSION_FILE"
