# EC2 Runtime Validation

Validated on 2026-06-20 in `us-west-2`.

```text
Instance ID: i-070fe5055535eead6
Observed public IPv4: 44.228.97.60
Private IPv4: 10.0.1.36
Operating system: Debian 13 Trixie, amd64
Validated repository commit: f6514ed
Kamailio: 6.1.3
RTPEngine: 13.5.1.16
MariaDB: 11.8.6
Packaged Certbot: 4.0.0
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
- Nginx and coturn are inactive as expected at this checkpoint.

## Remaining

- Confirm the observed public address is a CloudFormation-managed Elastic IP.
- Install Certbot 5.4 or newer for short-lived IP-address certificate support.
- Temporarily allow public TCP port 80, issue and test the certificate, then remove the rule.
- Enable Nginx, HTTPS, and WSS and rerun the expanded health check.
- Resolve the browser-client distribution task and validate two-way audio.
