#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

fail() {
  printf 'NOT READY: %s\n' "$*" >&2
  exit 1
}

[[ -d .git ]] || fail 'initialize this directory as a Git repository'
git rev-parse --verify HEAD >/dev/null 2>&1 || fail 'create the initial reviewed commit'

expected_origin=https://github.com/gary391/webrtc-to-sip-ec2.git
origin=$(git remote get-url origin 2>/dev/null || true)
[[ $origin == "$expected_origin" ]] ||
  fail "set Git remote origin to $expected_origin"

[[ ! -e .env ]] || {
  git check-ignore -q .env || fail '.env exists but is not ignored by Git'
}

git diff --check
[[ -z $(git status --porcelain) ]] || fail 'commit or discard all local changes'
make test

if command -v cfn-lint >/dev/null 2>&1; then
  cfn_lint=(cfn-lint)
elif command -v uvx >/dev/null 2>&1; then
  cfn_lint=(uvx --from 'cfn-lint<2' cfn-lint)
else
  fail 'install cfn-lint or uvx and rerun the readiness check'
fi
"${cfn_lint[@]}" infra/cloudformation/webrtc-to-sip-ec2.yaml

grep -Fq 'Default: https://github.com/gary391/webrtc-to-sip-ec2.git' \
  infra/cloudformation/webrtc-to-sip-ec2.yaml ||
  fail 'CloudFormation RepoUrl does not target the implementation repository'

if git ls-files --error-unmatch .env >/dev/null 2>&1; then
  fail '.env must never be tracked'
fi

printf 'Local infrastructure checks passed. GitHub CI and AWS inputs still require operator confirmation.\n'
