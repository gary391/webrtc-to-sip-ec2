#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
OUTPUT_FILE=${OUTPUT_FILE:-$ROOT_DIR/generated/client/config.js}
TEMPLATE_FILE=${TEMPLATE_FILE:-$ROOT_DIR/templates/client/config.js.template}

ENV_FILE=$ENV_FILE "$ROOT_DIR/deploy/common/validate-env.sh" >/dev/null

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

mkdir -p "$(dirname "$OUTPUT_FILE")"

python3 - "$TEMPLATE_FILE" "$OUTPUT_FILE" <<'PY'
import json
import os
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
mode = os.environ["ICE_MODE"]

if mode == "stun":
    servers = [{"urls": os.environ["STUN_URL"]}]
elif mode == "none":
    servers = []
elif mode == "turn":
    host = os.environ["TURN_REALM"]
    port = os.environ["TURN_PORT"]
    username = os.environ["TURN_USER"]
    credential = os.environ["TURN_PASSWORD"]
    servers = [
        {
            "urls": f"turn:{host}:{port}?transport=udp",
            "username": username,
            "credential": credential,
        },
        {
            "urls": f"turn:{host}:{port}?transport=tcp",
            "username": username,
            "credential": credential,
        },
    ]
else:
    raise SystemExit(f"unsupported ICE_MODE: {mode}")

replacements = {
    "__SIP_DOMAIN__": json.dumps(os.environ["DOMAIN"]),
    "__WEB_SOCKET_URI__": json.dumps(f"wss://{os.environ['DOMAIN']}/ws"),
    "__DEFAULT_SIP_USER__": json.dumps(os.environ["SIP_USER"]),
    "__DEFAULT_PEER_USER__": json.dumps(os.environ["SIP_PEER_USER"]),
    "__ICE_SERVERS__": json.dumps(servers, indent=2),
}
rendered = template_path.read_text(encoding="utf-8")
for placeholder, value in replacements.items():
    rendered = rendered.replace(placeholder, value)
output_path.write_text(rendered, encoding="utf-8")
PY

printf 'Rendered %s ICE configuration to %s\n' "$ICE_MODE" "$OUTPUT_FILE"
