#!/usr/bin/env bash
set -euo pipefail

SSH_HOST=${SSH_HOST:-kamdemo}
REMOTE_SOURCE_DIR=${REMOTE_SOURCE_DIR:-/opt/webrtc-to-sip/source}
AWS_REGION=${AWS_REGION:-}
INSTANCE_ID=${INSTANCE_ID:-}
SECURITY_GROUP_ID=${SECURITY_GROUP_ID:-}
PUBLIC_IPV4=${PUBLIC_IPV4:-}
ACME_CIDR=${ACME_CIDR:-0.0.0.0/0}
ACME_RULE_DESCRIPTION=${ACME_RULE_DESCRIPTION:-Temporary ACME HTTP-01 validation}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

remote_metadata() {
  local path=$1
  ssh "$SSH_HOST" \
    "set -euo pipefail; TOKEN=\$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60'); curl -fsS -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/${path}"
}

revoke_rule() {
  if [[ -n ${added_rule_id:-} ]]; then
    printf 'Removing temporary ACME ingress rule %s from %s...\n' "$added_rule_id" "$SECURITY_GROUP_ID"
    aws ec2 revoke-security-group-ingress \
      --region "$AWS_REGION" \
      --group-id "$SECURITY_GROUP_ID" \
      --security-group-rule-ids "$added_rule_id" >/dev/null || \
      printf 'ERROR: failed to remove temporary ACME ingress rule %s.\n' "$added_rule_id" >&2
  fi
}

require_command aws
require_command ssh

[[ $ACME_CIDR == "0.0.0.0/0" ]] ||
  fail "ACME_CIDR must be 0.0.0.0/0 for Let's Encrypt HTTP-01 validation"

if [[ -z $INSTANCE_ID ]]; then
  INSTANCE_ID=$(remote_metadata instance-id)
fi
if [[ -z $AWS_REGION ]]; then
  AWS_REGION=$(remote_metadata placement/region)
fi
if [[ -z $PUBLIC_IPV4 ]]; then
  PUBLIC_IPV4=$(remote_metadata public-ipv4)
fi
if [[ -z $SECURITY_GROUP_ID ]]; then
  SECURITY_GROUP_ID=$(
    aws ec2 describe-instances \
      --region "$AWS_REGION" \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
      --output text
  )
fi

[[ -n $INSTANCE_ID && $INSTANCE_ID != None ]] || fail "could not resolve INSTANCE_ID"
[[ -n $AWS_REGION && $AWS_REGION != None ]] || fail "could not resolve AWS_REGION"
[[ -n $PUBLIC_IPV4 && $PUBLIC_IPV4 != None ]] || fail "could not resolve PUBLIC_IPV4"
[[ -n $SECURITY_GROUP_ID && $SECURITY_GROUP_ID != None ]] ||
  fail "could not resolve SECURITY_GROUP_ID"

existing_rule=$(
  aws ec2 describe-security-group-rules \
    --region "$AWS_REGION" \
    --filters "Name=group-id,Values=$SECURITY_GROUP_ID" \
    --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol==\`tcp\` && FromPort==\`80\` && ToPort==\`80\` && CidrIpv4==\`${ACME_CIDR}\`].SecurityGroupRuleId" \
    --output text
)
[[ -z $existing_rule ]] ||
  fail "public TCP/80 ingress already exists on $SECURITY_GROUP_ID: $existing_rule"

printf 'Adding temporary ACME ingress rule to %s in %s...\n' "$SECURITY_GROUP_ID" "$AWS_REGION"
added_rule_id=$(
  aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"IpRanges\":[{\"CidrIp\":\"${ACME_CIDR}\",\"Description\":\"${ACME_RULE_DESCRIPTION}\"}]}]" \
    --query 'SecurityGroupRules[0].SecurityGroupRuleId' \
    --output text
)
[[ -n $added_rule_id && $added_rule_id != None ]] ||
  fail "failed to add temporary ACME ingress rule"
trap revoke_rule EXIT

printf 'Running staging and production certificate renewal on %s...\n' "$SSH_HOST"
ssh "$SSH_HOST" \
  "cd '$REMOTE_SOURCE_DIR' && sudo ACME_STAGING=true make renew-ip-certificate && sudo ACME_STAGING=false make renew-ip-certificate"

printf 'Verifying renewed certificate and nginx locally on the instance...\n'
ssh "$SSH_HOST" \
  "curl --max-time 10 -k -I -s https://127.0.0.1/ | head -5 && sudo openssl x509 -in '/etc/letsencrypt/live/${PUBLIC_IPV4}/fullchain.pem' -noout -dates"

revoke_rule
added_rule_id=""
trap - EXIT

printf 'IP certificate renewal completed and temporary ACME ingress was removed.\n'
