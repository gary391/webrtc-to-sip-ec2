# IP Certificate Renewal

The demo uses a short-lived Let's Encrypt certificate for its Elastic IP.
Automatic renewal is intentionally disabled because HTTP-01 requires a brief,
public TCP port 80 validation window and the IP-capable Certbot is installed at
`/usr/local/bin/certbot-ip`, separate from Debian's packaged client.

Renew one to two days before the current expiry date. The EC2 instance must be
running during renewal.

## Check expiry

```bash
ssh kamdemo
sudo openssl x509 \
  -in "/etc/letsencrypt/live/${PUBLIC_IPV4}/fullchain.pem" \
  -noout -subject -issuer -dates
```

## Automated renewal wrapper

From the workstation, run:

```bash
./scripts/renew-ec2-ip-certificate.sh
```

Defaults:

```text
SSH_HOST=kamdemo
REMOTE_SOURCE_DIR=/opt/webrtc-to-sip/source
ACME_CIDR=0.0.0.0/0
```

The wrapper discovers the instance ID and AWS region through IMDSv2 over SSH,
finds the instance security group with AWS CLI, adds a temporary public TCP/80
rule, runs staging then production renewal on the instance, verifies local HTTPS
and certificate dates, and removes the temporary TCP/80 rule in an exit trap.

Override `INSTANCE_ID`, `AWS_REGION`, or `SECURITY_GROUP_ID` when SSH metadata
discovery or EC2 lookup is not desired:

```bash
AWS_REGION=us-west-2 \
INSTANCE_ID=i-0123456789abcdef0 \
SECURITY_GROUP_ID=sg-0123456789abcdef0 \
./scripts/renew-ec2-ip-certificate.sh
```

## Open the validation window

In the EC2 console, open the instance security group and temporarily add this
inbound rule:

```text
Type: HTTP
Protocol: TCP
Port: 80
Source: 0.0.0.0/0
Description: Temporary ACME HTTP-01 validation
```

Restricting the source to the demo workstation will not work because Let's
Encrypt validation systems must reach the standalone challenge server.

## Test and renew

From `/opt/webrtc-to-sip/source` on the instance, validate against staging
before contacting production:

```bash
sudo ACME_STAGING=true make renew-ip-certificate
sudo ACME_STAGING=false make renew-ip-certificate
```

The command stops nginx only while Certbot owns port 80. A trap restores nginx
after success or failure. Production renewal updates the existing
`/etc/letsencrypt/live/${PUBLIC_IPV4}/` lineage and prints the new validity dates.

## Close and verify

Immediately remove the temporary HTTP rule from the security group, then run:

```bash
systemctl is-active nginx kamailio rtpengine-daemon mariadb
curl -I "https://${PUBLIC_IPV4}/"
sudo openssl x509 \
  -in "/etc/letsencrypt/live/${PUBLIC_IPV4}/fullchain.pem" \
  -noout -dates
```

All four services must report `active`, HTTPS must return `200`, and the
certificate must show a later `notAfter` value.
