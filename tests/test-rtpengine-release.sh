#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
record=$(
  ENV_FILE=/dev/null \
  RTPENGINE_RELEASES_JSON_FILE=$ROOT_DIR/tests/fixtures/rtpengine-releases.json \
  "$ROOT_DIR/deploy/native/resolve-rtpengine-release.sh"
)

IFS=$'\t' read -r tag name url digest <<< "$record"
[[ $tag == mr13.5.1.16 ]]
[[ $name == rtpengine-daemon_13.5.1.16+0~mr13.5.1.16+gh+trixie_amd64.deb ]]
[[ $url == https://github.com/sipwise/rtpengine/releases/download/mr13.5.1.16/current.deb ]]
[[ $digest == d85719f9271b66970d82c0839a9614597bad485a1320e881b9a400586258901d ]]

jq '.[2].assets[1].digest = null' "$ROOT_DIR/tests/fixtures/rtpengine-releases.json" \
  > "$TMP_DIR/missing-digest.json"
if ENV_FILE=/dev/null RTPENGINE_RELEASES_JSON_FILE=$TMP_DIR/missing-digest.json \
  "$ROOT_DIR/deploy/native/resolve-rtpengine-release.sh" >/dev/null 2>&1; then
  printf 'RTPEngine release without a digest unexpectedly passed\n' >&2
  exit 1
fi

jq '.[2].assets[1].browser_download_url = "https://example.invalid/current.deb"' \
  "$ROOT_DIR/tests/fixtures/rtpengine-releases.json" > "$TMP_DIR/bad-url.json"
if ENV_FILE=/dev/null RTPENGINE_RELEASES_JSON_FILE=$TMP_DIR/bad-url.json \
  "$ROOT_DIR/deploy/native/resolve-rtpengine-release.sh" >/dev/null 2>&1; then
  printf 'RTPEngine release from an untrusted URL unexpectedly passed\n' >&2
  exit 1
fi

printf 'RTPEngine release resolution tests passed.\n'
