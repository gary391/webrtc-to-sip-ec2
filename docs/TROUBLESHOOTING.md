# Troubleshooting

- **SSH or HTTPS blocked:** re-check the workstation public IP and stack CIDRs.
- **Certificate issuance fails:** locked port 80 prevents HTTP-01; use DNS-01 or
  a deliberate temporary restricted HTTP rule.
- **WebSocket fails:** run `nginx -t`, inspect `/ws`, and check Kamailio port 8080.
- **Registration fails:** inspect the domain, subscriber record, password, and
  Kamailio authentication logs.
- **One-way/no audio:** compare RTPEngine private/public interface values with
  SDP and the security-group RTP range.
- **STUN fails:** try none only as a diagnostic; enable TURN only after evidence.
- **CPU/memory/disk pressure:** inspect CPU credits, `free -h`, `df -h`, and journals.

Useful commands:

```bash
ip addr
ip route
ss -lntup
journalctl -u kamailio -u rtpengine-daemon -u nginx -u mariadb -n 200 --no-pager
make collect-debug
```
