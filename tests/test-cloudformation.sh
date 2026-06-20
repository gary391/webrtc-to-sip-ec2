#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE=$ROOT_DIR/infra/cloudformation/webrtc-to-sip-ec2.yaml

ruby -rpsych -e 'Psych.parse_file(ARGV.fetch(0))' "$TEMPLATE"

if sed -n '/SecurityGroupIngress:/,/SecurityGroupEgress:/p' "$TEMPLATE" |
  grep -Fq 'CidrIp: 0.0.0.0/0'; then
  printf 'Template contains broad ingress\n' >&2
  exit 1
fi

for expected in \
  'Default: t3.medium' \
  'Default: standard' \
  'Default: 30' \
  'Default: gp3' \
  'Default: /aws/service/debian/release/13/latest/amd64' \
  'Default: 30000' \
  'Default: 30039' \
  "Default: 'false'"; do
  grep -Fq "$expected" "$TEMPLATE" || {
    printf 'Template is missing expected default: %s\n' "$expected" >&2
    exit 1
  }
done

if grep -Fq 'Debian 12' "$TEMPLATE"; then
  printf 'Template still references Debian 12\n' >&2
  exit 1
fi

grep -Fq 'Default: https://github.com/gary391/webrtc-to-sip-ec2.git' "$TEMPLATE" || {
  printf 'Template RepoUrl does not target the implementation repository\n' >&2
  exit 1
}

printf 'CloudFormation static checks passed.\n'
