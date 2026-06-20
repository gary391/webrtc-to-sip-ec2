# Spec Review

Reviewed on 2026-06-20 against upstream commit
`65d9e7684ce3fb140a147470268e8dd50c8f243a` (2023-10-19).

## Findings

### 1. Operating-system and AMI selection needed a version policy

The original parameter list had no AMI input or regional lookup. AMI IDs are
regional, and Debian 12 is now oldstable. The implementation targets the current
stable release, Debian 13 Trixie, and resolves the newest official amd64 image
within that major release from the public SSM parameter
`/aws/service/debian/release/13/latest/amd64`. This follows security refreshes
without silently moving to a future, untested Debian major release.

### 2. Numeric cross-parameter validation is not available in template rules

CloudFormation parameter rules support equality and membership checks, but not
numeric greater-than comparisons. The requirement that `RtpPortMax` be greater
than or equal to `RtpPortMin` is therefore enforced by `validate-env.sh` and by
the EC2 security-group API at deployment time. A CI linter should also check
the template defaults. Adding a Lambda-backed custom resource for this would be
disproportionate for the demo.

### 3. Source CIDR assumptions are narrower than common RTP behavior

Restricting RTP to the workstation's current public `/32` is appropriate for
the stated personal demo, but it will fail when a SIP peer or provider sends
media from a different address. The operator must update `DemoClientCidr` to a
known peer CIDR rather than broadly opening the range. This is a demo constraint,
not a generally deployable SIP topology.

### 4. TLS bootstrap is not fully defined

HTTPS/WSS is required, while port 80 is off and the spec permits several
certificate methods without selecting one. Native configuration cannot be fully
automatic until a domain and certificate source are selected. The stack creates
DNS only when both hosted-zone and domain parameters are supplied; certificate
issuance remains an explicit deployment task.

### 5. The upstream configuration is a reference, not a safe install source

Upstream targets Debian 12 and includes fixed `websip/websip` credentials, TURN-first browser
configuration, TLS 1.0/1.1, a different RTP range, IPv6 listeners, and a legacy
Sipwise package flow. Those files must be adapted, not copied verbatim. Upstream
also has no release and its latest commit is from 2023, so package names and
configuration syntax need validation on a fresh Debian 13 instance.

### 6. Secrets need a clear runtime ownership model

The spec correctly excludes secrets from CloudFormation user data and outputs,
but `.env` still contains high-value credentials. The implementation rejects
placeholder values and ignores `.env`; native configuration must additionally
install rendered secret-bearing files with restrictive permissions. Secrets
Manager is intentionally not added to this small demo unless desired later.

## Decisions for the first slice

- Create a dedicated VPC and public subnet for deterministic cleanup.
- Resolve the newest official Debian 13 amd64 AMI through Debian's public SSM parameter.
- Track the latest patch in Kamailio's stable 6.1 package series for Trixie.
- Track the latest patch in upstream's stable RTPEngine 13.5 series with Trixie packages.
- Require IMDSv2 and encrypt the root EBS volume.
- Attach only `AmazonSSMManagedInstanceCore` to the instance role.
- Keep all inbound rules restricted to the supplied `/32` CIDRs.
- Keep TURN rules conditional and use a separate `31000-31039/udp` range.
- Keep clone-on-boot optional and do not install telephony services in user data.
