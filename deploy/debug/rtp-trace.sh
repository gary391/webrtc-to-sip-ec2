#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
exec sudo tcpdump -ni any "udp portrange $RTPENGINE_PORT_MIN-$RTPENGINE_PORT_MAX"
