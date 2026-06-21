# Troubleshooting

- **SSH or HTTPS blocked:** re-check the workstation public IP and stack CIDRs.
- **Certificate issuance fails:** locked port 80 prevents HTTP-01. Prefer DNS-01
  with a domain, or deliberately allow public ACME validation only for the
  issuance window. Restricting HTTP to `DemoClientCidr` does not allow the CA's
  validation systems to reach the challenge.
- **IP certificate cannot be requested:** confirm the Elastic IP is attached and
  the ACME client supports short-lived IP-address certificates. Certbot's
  documented webroot support requires version 5.4 or newer.
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

If Kamailio failed during boot because MariaDB was not ready, apply the service
dependency and restart it:

```bash
sudo make native-configure-kamailio
sudo systemctl enable --now kamailio
```

The configured systemd drop-in requires MariaDB and orders Kamailio after it on
subsequent boots.
