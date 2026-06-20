# Version Policy

## Debian

The deployment targets Debian 13 (Trixie), the current stable Debian release as
of 2026-06-20. CloudFormation resolves the newest official amd64 AMI published
within the Debian 13 major release using:

```text
/aws/service/debian/release/13/latest/amd64
```

This gives new Debian 13 security-refresh AMIs without automatically adopting a
future Debian major release. Moving to Debian 14 will be an explicit reviewed
change with package installation and media-path smoke tests.

## Kamailio

The native install path targets the current stable Kamailio 6.1 series from the
official Kamailio repository for Trixie:

```text
https://deb.kamailio.org/kamailio61
```

APT may install newer 6.1.x patch releases. A move to Kamailio 6.2 or later must
be reviewed because configuration directives, module packaging, database schema,
and RTPEngine integration can change between major/minor series.

## RTPEngine

The native install path targets the latest patch in the upstream-stable
RTPEngine 13.5 series. As of 2026-06-20, Sipwise marks `mr13.5.1.16` as the
latest release and publishes Debian Trixie amd64 packages for it.

```text
https://github.com/sipwise/rtpengine/releases
```

Debian 13's distribution package is currently RTPEngine 12.5.1.31. It is a
supported fallback, but it does not satisfy this project's latest-release
policy. Sipwise also publishes higher-numbered `mr26` builds; those are not
selected merely because the number is larger. Moving away from the release
series marked stable by upstream requires explicit compatibility testing with
Kamailio, DTLS-SRTP, ICE handling, systemd, and the configured kernel.

The installer must select a Trixie amd64 release asset, verify its published
SHA-256 digest, and record the resolved package version. It must never download
an unversioned artifact without checksum verification.

The planned installer must log the resolved versions with:

```bash
cat /etc/os-release
kamailio -V
rtpengine --version
```
