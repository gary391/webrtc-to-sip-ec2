#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
elif [[ ${ALLOW_ENV_ONLY:-false} != true ]]; then
  fail "environment file not found: $ENV_FILE"
fi

required=(
  DOMAIN DEBIAN_CODENAME KAMAILIO_SERIES KAMAILIO_APT_REPOSITORY
  RTPENGINE_SERIES RTPENGINE_RELEASE_REPOSITORY
  PUBLIC_IPV4 PRIVATE_IPV4
  ADMIN_CIDR DEMO_CLIENT_CIDR SIP_USER SIP_PASSWORD SIP_PEER_USER SIP_PEER_PASSWORD
  DB_ROOT_PASSWORD DB_KAMAILIO_NAME DB_KAMAILIO_USER DB_KAMAILIO_PASSWORD
  ICE_MODE ENABLE_TURN
  RTPENGINE_PORT_MIN RTPENGINE_PORT_MAX RTPENGINE_CONTROL_IP
  RTPENGINE_CONTROL_PORT KAMAILIO_WS_INTERNAL_PORT
  KAMAILIO_WSS_INTERNAL_PORT KAMAILIO_SIP_PORT WEB_CLIENT_ROOT
  TLS_CERT_PATH TLS_KEY_PATH ENABLE_NGINX
)

for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || fail "$name is required"
done

[[ $DEBIAN_CODENAME == trixie ]] ||
  fail "DEBIAN_CODENAME must be trixie for the current Debian 13 baseline"
[[ $KAMAILIO_SERIES == 6.1 ]] ||
  fail "KAMAILIO_SERIES must be the reviewed stable 6.1 series"
[[ $KAMAILIO_APT_REPOSITORY == https://deb.kamailio.org/kamailio61 ]] ||
  fail "KAMAILIO_APT_REPOSITORY must use the official Kamailio 6.1 repository"
[[ $RTPENGINE_SERIES == 13.5 ]] ||
  fail "RTPENGINE_SERIES must be the reviewed upstream-stable 13.5 series"
[[ $RTPENGINE_RELEASE_REPOSITORY == https://github.com/sipwise/rtpengine/releases ]] ||
  fail "RTPENGINE_RELEASE_REPOSITORY must use the official Sipwise releases"
[[ $DB_KAMAILIO_NAME =~ ^[a-z][a-z0-9_]{0,31}$ ]] ||
  fail "DB_KAMAILIO_NAME must be a simple lowercase SQL identifier"
[[ $DB_KAMAILIO_USER =~ ^[a-z][a-z0-9_]{0,31}$ ]] ||
  fail "DB_KAMAILIO_USER must be a simple lowercase SQL identifier"

is_bool() {
  [[ $1 == true || $1 == false ]]
}

is_port() {
  [[ $1 =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

validate_range() {
  local min_name=$1
  local max_name=$2
  local min=${!min_name}
  local max=${!max_name}
  is_port "$min" || fail "$min_name must be an integer from 1 to 65535"
  is_port "$max" || fail "$max_name must be an integer from 1 to 65535"
  (( 10#$max >= 10#$min )) || fail "$max_name must be greater than or equal to $min_name"
}

validate_demo_cidr() {
  local name=$1
  local value=${!name}
  [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/32$ ]] ||
    fail "$name must be a single-host IPv4 /32 CIDR"
  [[ $value != 0.0.0.0/0 ]] || fail "$name must not allow the entire internet"

  local address=${value%/32}
  local octet
  IFS=. read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || fail "$name contains an invalid IPv4 octet"
  done
}

validate_secret() {
  local name=$1
  local value=${!name}
  [[ $value != change-me && $value != websip ]] || fail "$name still uses an unsafe default"
  (( ${#value} >= 16 )) || fail "$name must contain at least 16 characters"
  [[ $value =~ ^[A-Za-z0-9._~!@#%+=^-]+$ ]] ||
    fail "$name contains characters that cannot be rendered safely"
}

validate_ipv4() {
  local name=$1
  local value=${!name}
  local octet
  [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "$name must be an IPv4 address"
  IFS=. read -r -a octets <<< "$value"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || fail "$name contains an invalid IPv4 octet"
  done
}

validate_demo_cidr ADMIN_CIDR
validate_demo_cidr DEMO_CLIENT_CIDR
validate_ipv4 PUBLIC_IPV4
validate_ipv4 PRIVATE_IPV4
[[ $DOMAIN =~ ^[A-Za-z0-9.-]{1,253}$ ]] || fail "DOMAIN contains unsupported characters"
for name in SIP_USER SIP_PEER_USER; do
  [[ ${!name} =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || fail "$name contains unsupported characters"
done
[[ $SIP_USER != "$SIP_PEER_USER" ]] || fail "SIP_USER and SIP_PEER_USER must be different"
validate_secret SIP_PASSWORD
validate_secret SIP_PEER_PASSWORD
validate_secret DB_ROOT_PASSWORD
validate_secret DB_KAMAILIO_PASSWORD
[[ $DB_KAMAILIO_PASSWORD =~ ^[A-Za-z0-9._~-]+$ ]] ||
  fail "DB_KAMAILIO_PASSWORD must contain only URL-safe unreserved characters"

[[ $ICE_MODE == stun || $ICE_MODE == none || $ICE_MODE == turn ]] ||
  fail "ICE_MODE must be one of: stun, none, turn"
is_bool "$ENABLE_TURN" || fail "ENABLE_TURN must be true or false"
is_bool "$ENABLE_NGINX" || fail "ENABLE_NGINX must be true or false"
[[ $WEB_CLIENT_ROOT == /* ]] || fail "WEB_CLIENT_ROOT must be an absolute path"
[[ $TLS_CERT_PATH == /* ]] || fail "TLS_CERT_PATH must be an absolute path"
[[ $TLS_KEY_PATH == /* ]] || fail "TLS_KEY_PATH must be an absolute path"

case "$ICE_MODE" in
  stun)
    [[ ${STUN_URL:-} == stun:* || ${STUN_URL:-} == stuns:* ]] ||
      fail "ICE_MODE=stun requires STUN_URL with a stun: or stuns: scheme"
    ;;
  turn)
    [[ $ENABLE_TURN == true ]] || fail "ICE_MODE=turn requires ENABLE_TURN=true"
    for name in TURN_USER TURN_PASSWORD TURN_REALM TURN_PORT TURN_RELAY_PORT_MIN TURN_RELAY_PORT_MAX; do
      [[ -n ${!name:-} ]] || fail "$name is required when TURN is enabled"
    done
    validate_secret TURN_PASSWORD
    is_port "$TURN_PORT" || fail "TURN_PORT must be an integer from 1 to 65535"
    validate_range TURN_RELAY_PORT_MIN TURN_RELAY_PORT_MAX
    ;;
esac

validate_range RTPENGINE_PORT_MIN RTPENGINE_PORT_MAX

for name in RTPENGINE_CONTROL_PORT KAMAILIO_WS_INTERNAL_PORT KAMAILIO_WSS_INTERNAL_PORT KAMAILIO_SIP_PORT; do
  is_port "${!name}" || fail "$name must be an integer from 1 to 65535"
done

[[ $RTPENGINE_CONTROL_IP == 127.0.0.1 ]] ||
  fail "RTPENGINE_CONTROL_IP must remain bound to 127.0.0.1"

printf 'Environment validation passed (ICE_MODE=%s, TURN=%s).\n' "$ICE_MODE" "$ENABLE_TURN"
