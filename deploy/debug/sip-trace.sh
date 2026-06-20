#!/usr/bin/env bash
set -euo pipefail
exec sudo sngrep -d any port 5060
