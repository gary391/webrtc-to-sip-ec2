#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER=$ROOT_DIR/deploy/native/install.sh

required_patterns=(
  'requires Debian 13 Trixie'
  'dpkg --print-architecture'
  '/usr/share/keyrings/kamailio.gpg'
  'https://deb.kamailio.org/kamailiodebkey.gpg'
  'resolve-rtpengine-release.sh'
  'sha256sum --check --status'
  'systemctl disable --now'
  'installed-versions.txt'
)

for pattern in "${required_patterns[@]}"; do
  grep -Fq "$pattern" "$INSTALLER" || {
    printf 'Native installer is missing guardrail: %s\n' "$pattern" >&2
    exit 1
  }
done

if grep -Eq '(^|[[:space:]])apt-key([[:space:]]|$)' "$INSTALLER"; then
  printf 'Native installer uses deprecated apt-key\n' >&2
  exit 1
fi

printf 'Native installer static checks passed.\n'
