# EC2 Runtime Validation

Validated on 2026-06-20 in `us-west-2`.

```text
Instance ID: i-070fe5055535eead6
Observed public IPv4: 44.228.97.60
Private IPv4: 10.0.1.36
Operating system: Debian 13 Trixie, amd64
Validated repository commit: f2539ea
Kamailio: 6.1.3
RTPEngine: 13.5.1.16
MariaDB: 11.8.6
IP-capable Certbot: 5.6.0 (isolated under /opt/certbot-ip)
Certificate SAN: IP Address 44.228.97.60
Certificate expiry: 2026-06-27
```

## Verified

- SSH works with the Debian `admin` user and the selected EC2 key pair.
- IMDSv2 detection returns the expected region, instance ID, and addresses.
- The private GitHub repository clones using a read-only EC2 deploy key.
- All 12 repository test groups pass on Debian.
- Native package installation succeeds with services held inactive until configured.
- MariaDB listens only on `127.0.0.1:3306`.
- RTPEngine control listens only on `127.0.0.1:22222`.
- Kamailio listens on the private address for SIP and loopback for WebSocket.
- MariaDB, RTPEngine, and Kamailio are active and pass the default-mode health check.
- A staging and production short-lived IP certificate were issued with HTTP-01.
- Nginx is active with trusted HTTPS and the WSS proxy configuration.
- The expanded on-instance health check passes, including HTTPS on TCP 443.
- External HTTPS returns HTTP 200 with the expected security headers.
- JsSIP 3.13.8 and its MIT license are served locally with the reviewed checksum.
- The `websip` and `softphone` subscribers exist for the IP-address realm.
- Authenticated JsSIP registration succeeds over the public trusted WSS path.
- Coturn is inactive as expected in the default STUN-first mode.

## Remaining

- Confirm the observed public address is a CloudFormation-managed Elastic IP.
- Reopen port 80 near certificate expiry for manual renewal unless validation
  access is deliberately automated.
- Register a desktop SIP softphone as `softphone` and validate two-way audio,
  dialog teardown, and relay rejection.
