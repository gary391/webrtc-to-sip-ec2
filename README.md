# WebRTC-to-SIP on EC2

Native Debian 13 deployment tooling for a small, locked-down WebRTC-to-SIP
demo on one AWS EC2 instance. The default media discovery mode is STUN;
coturn and TURN ingress are disabled unless explicitly enabled.

## Current scope

The first implementation slice includes:

- a CloudFormation baseline for the VPC, subnet, security group, IAM role,
  EC2 instance, optional Elastic IP, and optional Route 53 record
- environment validation for credentials, ICE mode, CIDRs, and port ranges
- deterministic browser `iceServers` rendering for STUN, none, and TURN modes
- IMDSv2-only EC2 environment discovery with no IMDSv1 fallback
- a Debian 13 native package installer with guarded Kamailio and RTPEngine sources
- a tracked backlog in [TASKS.md](TASKS.md)

The native installer still needs its Debian EC2 smoke test. Kamailio, RTPEngine,
Nginx, and MariaDB configuration is tracked but is not yet complete. MariaDB
and RTPEngine configuration implementations are present and awaiting that smoke
test; Kamailio and Nginx are the next local implementation tasks.

## Quick checks

```bash
cp .env.example .env
# Replace every change-me value before validating.
make validate-env
make test
make validate-cloudformation
```

On the Debian EC2 host:

```bash
sudo make detect-ec2-env
sudo make native-install
```

The installer leaves all network services disabled until configuration is
rendered and validated.

CloudFormation resolves the latest official Debian 13 amd64 AMI in the selected
region through Debian's AWS Systems Manager public parameter. Native service
installation will use the latest patch from Kamailio's stable 6.1 package series
for Debian Trixie and the latest upstream-stable RTPEngine 13.5.x release with
Trixie packages.

See [docs/VERSION_POLICY.md](docs/VERSION_POLICY.md) for the upgrade policy.

The browser demo uses a pinned, locally served JsSIP bundle under its MIT
license. See [docs/BROWSER_CLIENT.md](docs/BROWSER_CLIENT.md) for credentials,
build provenance, and call-test instructions.

## Development workflow

The planned implementation repository is:

```text
https://github.com/gary391/webrtc-to-sip-ec2
```

GitHub is the source of truth. Changes are developed and tested locally, pushed
to GitHub, then pulled onto the Debian EC2 host for runtime validation. See
[docs/DEVELOPMENT_WORKFLOW.md](docs/DEVELOPMENT_WORKFLOW.md).
