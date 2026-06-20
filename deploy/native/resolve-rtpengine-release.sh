#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$ROOT_DIR/.env}
RELEASES_JSON_FILE=${RTPENGINE_RELEASES_JSON_FILE:-}

if [[ -f $ENV_FILE ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

series=${RTPENGINE_SERIES:-13.5}
release_repository=${RTPENGINE_RELEASE_REPOSITORY:-https://github.com/sipwise/rtpengine/releases}

[[ $series == 13.5 ]] || {
  printf 'ERROR: unsupported RTPEngine series: %s\n' "$series" >&2
  exit 1
}
[[ $release_repository == https://github.com/sipwise/rtpengine/releases ]] || {
  printf 'ERROR: unsupported RTPEngine release repository: %s\n' "$release_repository" >&2
  exit 1
}

temp_file=
if [[ -n $RELEASES_JSON_FILE ]]; then
  releases_file=$RELEASES_JSON_FILE
else
  temp_file=$(mktemp)
  trap 'rm -f "$temp_file"' EXIT
  curl --fail --silent --show-error --location --retry 3 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    'https://api.github.com/repos/sipwise/rtpengine/releases?per_page=100' \
    > "$temp_file"
  releases_file=$temp_file
fi

jq -er --arg prefix "mr${series}." '
  map(select(
    (.draft | not) and
    (.prerelease | not) and
    (.tag_name | startswith($prefix))
  ))
  | sort_by(.published_at)
  | last as $release
  | if $release == null then
      error("no stable release found for " + $prefix)
    else
      $release
    end
  | [
      .assets[]
      | select(.name | test("^rtpengine-daemon_.*\\+trixie_amd64\\.deb$"))
      | select(.name | contains("dbgsym") | not)
    ] as $assets
  | if ($assets | length) != 1 then
      error("expected exactly one Trixie amd64 daemon asset")
    else
      $assets[0]
    end
  | if (.browser_download_url | startswith("https://github.com/sipwise/rtpengine/releases/download/") | not) then
      error("release asset is not hosted under the official Sipwise release path")
    else
      .
    end
  | (.digest // "") as $digest
  | if ($digest | test("^sha256:[0-9a-f]{64}$") | not) then
      error("release asset has no valid SHA-256 digest")
    else
      [$release.tag_name, .name, .browser_download_url, ($digest | sub("^sha256:"; ""))]
      | @tsv
    end
' "$releases_file"
