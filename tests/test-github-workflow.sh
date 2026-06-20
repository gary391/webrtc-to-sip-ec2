#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW=$ROOT_DIR/.github/workflows/validate.yml

for expected in \
  'permissions:' \
  'contents: read' \
  'make test' \
  'cfn-lint infra/cloudformation/webrtc-to-sip-ec2.yaml'; do
  grep -Fq "$expected" "$WORKFLOW" || {
    printf 'GitHub workflow is missing: %s\n' "$expected" >&2
    exit 1
  }
done

if grep -Eqi '(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|password:|token:)' "$WORKFLOW"; then
  printf 'GitHub workflow unexpectedly references deployment credentials\n' >&2
  exit 1
fi

printf 'GitHub workflow static tests passed.\n'
