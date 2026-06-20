# Validation

## Local and CI

```bash
make test
cfn-lint infra/cloudformation/webrtc-to-sip-ec2.yaml
make deploy-readiness
```

## EC2 package and configuration validation

```bash
make test
sudo make detect-ec2-env
sudo make native-install
sudo make native-configure
sudo make native-start
make native-status
make healthcheck
```

Expected listeners are HTTPS 443, SIP 5060, RTPEngine loopback control 22222,
and MariaDB loopback 3306. coturn should remain inactive by default.

## Call validation

Capture SIP with `make sip-trace`, RTP with `make rtp-trace`, and browser state
with `chrome://webrtc-internals`. Confirm REGISTER/200, INVITE/100/180/200/ACK,
two-way media in UDP 30000-30039, and BYE/200.
