#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR=${OUTPUT_DIR:-/tmp/webrtc-to-sip-debug-$(date +%Y%m%dT%H%M%S)}
install -d -m 0700 "$OUTPUT_DIR"

{
  date --iso-8601=seconds
  uname -a
  cat /etc/os-release
  ip addr
  ip route
  ss -lntup
  systemctl --no-pager --full status mariadb rtpengine-daemon kamailio nginx coturn || true
} > "$OUTPUT_DIR/system.txt" 2>&1

for service in mariadb rtpengine-daemon kamailio nginx coturn; do
  journalctl -u "$service" -n 300 --no-pager > "$OUTPUT_DIR/$service.log" 2>&1 || true
done

if [[ -r /etc/rtpengine/rtpengine.conf ]]; then
  cp /etc/rtpengine/rtpengine.conf "$OUTPUT_DIR/rtpengine.conf"
fi
if [[ -r /etc/nginx/sites-available/webrtc-to-sip.conf ]]; then
  cp /etc/nginx/sites-available/webrtc-to-sip.conf "$OUTPUT_DIR/nginx.conf"
fi
if [[ -r /etc/kamailio/kamailio.cfg ]]; then
  sed -E 's#mysql://[^:@]+:[^@]+@#mysql://REDACTED:REDACTED@#g' \
    /etc/kamailio/kamailio.cfg > "$OUTPUT_DIR/kamailio.redacted.cfg"
fi

archive=$OUTPUT_DIR.tar.gz
tar -C "$(dirname "$OUTPUT_DIR")" -czf "$archive" "$(basename "$OUTPUT_DIR")"
chmod 0600 "$archive"
printf 'Collected redacted debug bundle: %s\n' "$archive"
