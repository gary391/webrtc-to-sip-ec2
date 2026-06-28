#!/usr/bin/env bash
set -euo pipefail

IMDS_BASE_URL=${IMDS_BASE_URL:-http://169.254.169.254}
OUTPUT_FILE=${OUTPUT_FILE:-/opt/webrtc-to-sip/aws-instance.env}
CURL_BIN=${CURL_BIN:-curl}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

is_ipv4() {
  local value=$1
  local octet
  [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<< "$value"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

token=$(
  "$CURL_BIN" --fail --silent --show-error --connect-timeout 2 --max-time 5 \
    --request PUT \
    --header 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
    "$IMDS_BASE_URL/latest/api/token"
) || fail 'unable to acquire an IMDSv2 token; IMDSv1 fallback is not allowed'
[[ -n $token ]] || fail 'IMDSv2 returned an empty token'

imds_get() {
  "$CURL_BIN" --fail --silent --show-error --connect-timeout 2 --max-time 5 \
    --header "X-aws-ec2-metadata-token: $token" \
    "$IMDS_BASE_URL$1"
}

identity_document=$(imds_get /latest/dynamic/instance-identity/document) ||
  fail 'unable to read the EC2 instance identity document with IMDSv2'
public_ipv4=$(imds_get /latest/meta-data/public-ipv4) ||
  fail 'instance has no public IPv4 metadata; this demo requires a public address'

instance_id=$(jq -er '.instanceId | select(type == "string" and length > 0)' <<< "$identity_document") ||
  fail 'instance identity document has no instanceId'
private_ipv4=$(jq -er '.privateIp | select(type == "string" and length > 0)' <<< "$identity_document") ||
  fail 'instance identity document has no privateIp'
aws_region=$(jq -er '.region | select(type == "string" and length > 0)' <<< "$identity_document") ||
  fail 'instance identity document has no region'

[[ $instance_id =~ ^i-[a-zA-Z0-9]+$ ]] || fail 'metadata returned an invalid EC2 instance ID'
[[ $aws_region =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || fail 'metadata returned an invalid AWS region'
is_ipv4 "$private_ipv4" || fail 'metadata returned an invalid private IPv4 address'
is_ipv4 "$public_ipv4" || fail 'metadata returned an invalid public IPv4 address'

output_dir=$(dirname "$OUTPUT_FILE")
install -d -m 0755 "$output_dir"
temp_file=$(mktemp "$output_dir/.aws-instance.env.XXXXXX")
trap 'rm -f "$temp_file"' EXIT

{
  printf 'AWS_REGION=%s\n' "$aws_region"
  printf 'INSTANCE_ID=%s\n' "$instance_id"
  printf 'PRIVATE_IPV4=%s\n' "$private_ipv4"
  printf 'PUBLIC_IPV4=%s\n' "$public_ipv4"
} > "$temp_file"

chmod 0644 "$temp_file"
mv -f "$temp_file" "$OUTPUT_FILE"
trap - EXIT

printf 'Wrote EC2 metadata to %s using IMDSv2.\n' "$OUTPUT_FILE"
