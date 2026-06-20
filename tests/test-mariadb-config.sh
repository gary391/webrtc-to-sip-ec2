#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

OUTPUT_MODE=0644 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$ROOT_DIR/templates/mariadb/60-webrtc-to-sip.cnf.template" \
  "$TMP_DIR/mariadb.cnf"

grep -Fxq 'bind-address = 127.0.0.1' "$TMP_DIR/mariadb.cnf"
grep -Fxq 'skip-name-resolve' "$TMP_DIR/mariadb.cnf"
grep -Fxq 'local-infile = 0' "$TMP_DIR/mariadb.cnf"

script=$ROOT_DIR/deploy/native/configure-mariadb.sh
for required in \
  'standard-create.sql' \
  'auth_db-create.sql' \
  'usrloc-create.sql' \
  'GRANT SELECT, INSERT, UPDATE, DELETE' \
  "'127.0.0.1'" \
  'systemctl disable --now mariadb'; do
  grep -Fq "$required" "$script" || {
    printf 'MariaDB configuration is missing requirement: %s\n' "$required" >&2
    exit 1
  }
done

if grep -Fq 'GRANT ALL' "$script"; then
  printf 'MariaDB configuration grants excessive privileges\n' >&2
  exit 1
fi

printf 'MariaDB configuration static tests passed.\n'
