#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/mariadb/60-webrtc-to-sip.cnf.template}
OUTPUT_FILE=${OUTPUT_FILE:-/etc/mysql/mariadb.conf.d/60-webrtc-to-sip.cnf}
SCHEMA_DIR=${KAMAILIO_MYSQL_SCHEMA_DIR:-/usr/share/kamailio/mysql}

[[ $EUID -eq 0 ]] || {
  printf 'ERROR: MariaDB configuration must run as root.\n' >&2
  exit 1
}

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for schema in standard-create.sql auth_db-create.sql usrloc-create.sql; do
  [[ -r $SCHEMA_DIR/$schema ]] || {
    printf 'ERROR: required Kamailio schema is missing: %s/%s\n' "$SCHEMA_DIR" "$schema" >&2
    exit 1
  }
done

OUTPUT_MODE=0644 "$ROOT_DIR/deploy/common/render-template.sh" \
  "$TEMPLATE_FILE" "$OUTPUT_FILE"

root_defaults=$(mktemp)
trap 'rm -f "$root_defaults"; systemctl stop mariadb >/dev/null 2>&1 || true' EXIT
chmod 0600 "$root_defaults"
printf '[client]\nuser=root\npassword=%s\n' "$DB_ROOT_PASSWORD" > "$root_defaults"

systemctl restart mariadb

root_cli=(mariadb --protocol=socket --user=root)
if ! "${root_cli[@]}" --batch --skip-column-names --execute='SELECT 1' >/dev/null 2>&1; then
  root_cli=(mariadb "--defaults-extra-file=$root_defaults" --protocol=socket)
  "${root_cli[@]}" --batch --skip-column-names --execute='SELECT 1' >/dev/null || {
    printf 'ERROR: unable to authenticate as the local MariaDB root user.\n' >&2
    exit 1
  }
fi

"${root_cli[@]}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_KAMAILIO_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_KAMAILIO_USER}'@'127.0.0.1'
  IDENTIFIED BY '${DB_KAMAILIO_PASSWORD}';
ALTER USER '${DB_KAMAILIO_USER}'@'127.0.0.1'
  IDENTIFIED BY '${DB_KAMAILIO_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION
  FROM '${DB_KAMAILIO_USER}'@'127.0.0.1';
GRANT SELECT, INSERT, UPDATE, DELETE
  ON \`${DB_KAMAILIO_NAME}\`.* TO '${DB_KAMAILIO_USER}'@'127.0.0.1';
SQL

table_count=$(
  "${root_cli[@]}" --batch --skip-column-names --execute \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_KAMAILIO_NAME}'"
)

if [[ $table_count == 0 ]]; then
  for schema in standard-create.sql auth_db-create.sql usrloc-create.sql; do
    "${root_cli[@]}" "$DB_KAMAILIO_NAME" < "$SCHEMA_DIR/$schema"
  done
fi

for table in version subscriber location location_attrs; do
  exists=$(
    "${root_cli[@]}" --batch --skip-column-names --execute \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_KAMAILIO_NAME}' AND table_name='${table}'"
  )
  [[ $exists == 1 ]] || {
    printf 'ERROR: Kamailio database is partially initialized; missing table: %s\n' "$table" >&2
    exit 1
  }
done

"${root_cli[@]}" "$DB_KAMAILIO_NAME" <<SQL
INSERT INTO subscriber (username, domain, password, ha1, ha1b)
VALUES
  ('${SIP_USER}', '${DOMAIN}', '${SIP_PASSWORD}', '', ''),
  ('${SIP_PEER_USER}', '${DOMAIN}', '${SIP_PEER_PASSWORD}', '', '')
ON DUPLICATE KEY UPDATE
  password = VALUES(password),
  ha1 = '',
  ha1b = '';
SQL

"${root_cli[@]}" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL

systemctl disable --now mariadb >/dev/null 2>&1 || true
trap - EXIT
rm -f "$root_defaults"

printf 'Configured loopback-only MariaDB and Kamailio schema; service remains disabled.\n'
