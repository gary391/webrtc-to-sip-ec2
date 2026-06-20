#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/fake-curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
url=${!#}
case "$url" in
  */latest/api/token)
    [[ " $* " == *' --request PUT '* ]]
    printf 'test-token'
    ;;
  */latest/dynamic/instance-identity/document)
    [[ " $* " == *' X-aws-ec2-metadata-token: test-token '* ]]
    printf '{"instanceId":"i-0123456789abcdef0","privateIp":"10.0.1.25","region":"us-west-2"}'
    ;;
  */latest/meta-data/public-ipv4)
    [[ " $* " == *' X-aws-ec2-metadata-token: test-token '* ]]
    printf '203.0.113.10'
    ;;
  *) exit 22 ;;
esac
SH
chmod +x "$TMP_DIR/fake-curl"

export FAKE_CURL_LOG=$TMP_DIR/curl.log
CURL_BIN=$TMP_DIR/fake-curl IMDS_BASE_URL=http://imds.test \
  OUTPUT_FILE=$TMP_DIR/aws-instance.env \
  "$ROOT_DIR/deploy/common/detect-ec2-env.sh" >/dev/null

grep -Fxq 'AWS_REGION=us-west-2' "$TMP_DIR/aws-instance.env"
grep -Fxq 'EC2_INSTANCE_ID=i-0123456789abcdef0' "$TMP_DIR/aws-instance.env"
grep -Fxq 'PRIVATE_IPV4=10.0.1.25' "$TMP_DIR/aws-instance.env"
grep -Fxq 'PUBLIC_IPV4=203.0.113.10' "$TMP_DIR/aws-instance.env"
[[ $(stat -f '%Lp' "$TMP_DIR/aws-instance.env" 2>/dev/null || stat -c '%a' "$TMP_DIR/aws-instance.env") == 644 ]]
[[ $(wc -l < "$FAKE_CURL_LOG") -eq 3 ]]

cat > "$TMP_DIR/failing-curl" <<'SH'
#!/usr/bin/env bash
exit 22
SH
chmod +x "$TMP_DIR/failing-curl"
if CURL_BIN=$TMP_DIR/failing-curl OUTPUT_FILE=$TMP_DIR/should-not-exist \
  "$ROOT_DIR/deploy/common/detect-ec2-env.sh" >/dev/null 2>&1; then
  printf 'Metadata detection unexpectedly fell back after token failure\n' >&2
  exit 1
fi
[[ ! -e $TMP_DIR/should-not-exist ]]

printf 'IMDSv2 metadata detection tests passed.\n'
