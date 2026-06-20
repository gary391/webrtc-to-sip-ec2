#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
required=(
  docs/AWS_CLOUDFORMATION_DEPLOYMENT.md
  docs/DEVELOPMENT_WORKFLOW.md
  docs/REMOTE_DEV_WITH_VSCODE.md
  docs/LOCKED_DOWN_DEMO_NETWORKING.md
  docs/SECURITY_GROUPS.md
  docs/SECURITY.md
  docs/COST_GUARDRAILS.md
  docs/INSTANCE_SIZING.md
  docs/ICE_STUN_TURN_TROUBLESHOOTING.md
  docs/NATIVE_EC2_INSTALL.md
  docs/VALIDATION.md
  docs/TROUBLESHOOTING.md
  docs/CLEANUP.md
)

for file in "${required[@]}"; do
  [[ -s $ROOT_DIR/$file ]] || {
    printf 'Required documentation is missing or empty: %s\n' "$file" >&2
    exit 1
  }
done

printf 'Required file completeness tests passed.\n'
