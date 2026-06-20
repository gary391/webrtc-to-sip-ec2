# Native EC2 Installation

This phase installs packages on Debian 13 Trixie. It does not configure or start
the SIP/WebRTC services.

## Preconditions

- The host is an amd64 Debian 13 EC2 instance created by the CloudFormation template.
- The repository is available on the instance.
- `.env` has real secrets and passes `make validate-env`.
- Outbound HTTPS and Debian package access are available.

## Detect the instance environment

```bash
sudo make detect-ec2-env
cat /opt/webrtc-to-sip/aws-instance.env
```

The detector requires an IMDSv2 token. It reads the instance identity
document and public IPv4 metadata, validates the values, and atomically writes a
non-secret environment file. It never falls back to IMDSv1.

Merge `AWS_REGION`, `EC2_INSTANCE_ID`, `PRIVATE_IPV4`, and `PUBLIC_IPV4` into
the deployment `.env`, then validate:

```bash
make validate-env
```

## Install packages

```bash
sudo make native-install
```

The installer:

- verifies Debian 13 Trixie and amd64 before making changes
- temporarily prevents package post-install scripts from starting services
- installs baseline debugging tools, Nginx, MariaDB, and Certbot
- configures the signed official Kamailio 6.1 Trixie repository
- installs the Kamailio MySQL, TLS, WebSocket, and extra modules
- resolves the newest non-prerelease RTPEngine 13.5 Trixie amd64 daemon asset
- requires the official Sipwise GitHub download path and published SHA-256 digest
- installs coturn only when `ENABLE_TURN=true`
- records resolved versions in `/opt/webrtc-to-sip/installed-versions.txt`
- leaves all network services disabled until native configuration is complete

The RTPEngine installer currently uses userspace forwarding. This is adequate
for the 1-3 call demo and avoids making the initial deployment depend on DKMS or
kernel-module compatibility.

## Verify the package phase

```bash
cat /opt/webrtc-to-sip/installed-versions.txt
dpkg-query -W kamailio rtpengine-daemon nginx mariadb-server
systemctl is-enabled kamailio rtpengine-daemon nginx mariadb || true
```

The services should be installed but disabled. Do not enable them until the
configuration tasks have completed.

## Configuration currently available

After the package smoke test succeeds, the following guarded configuration
steps are available:

```bash
sudo make native-configure-mariadb
sudo make native-configure-rtpengine
```

MariaDB configuration binds to `127.0.0.1`, disables local file loading, imports
only the Kamailio `standard`, `auth_db`, and `usrloc` schemas, and grants the
runtime user only `SELECT`, `INSERT`, `UPDATE`, and `DELETE`.

RTPEngine configuration binds media to the EC2 private address, advertises the
public address, restricts its control socket to `127.0.0.1:22222`, and uses the
configured `30000-30039` range. The initial demo uses userspace forwarding
(`table = -1`) and does not require a kernel module.

Both commands leave their services disabled. They still require validation on
the Debian EC2 instance before their tracked tasks can be marked complete.

## DNS-less IP certificate

Debian 13's packaged Certbot is older than the version required for IP-address
certificates. Install a current client in an isolated virtual environment:

```bash
sudo make install-certbot-ip
sudo ACME_STAGING=true make issue-ip-certificate
sudo ACME_STAGING=false make issue-ip-certificate
```

Issuance uses the standalone HTTP-01 server and requires temporary public TCP
port 80 reachability. Staging files use separate `/etc/letsencrypt-staging`,
`/var/lib/letsencrypt-staging`, and `/var/log/letsencrypt-staging` directories.
Production certificates are written below `/etc/letsencrypt/live/<public-ip>/`.

IP certificates are short-lived. Closing port 80 after issuance means renewal
also requires temporarily reopening it. Do not enable automatic renewal until
security-group access for the validation window is deliberately automated.
