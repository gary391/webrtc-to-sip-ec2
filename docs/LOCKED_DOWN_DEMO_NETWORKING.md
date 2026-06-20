# Locked-Down Demo Networking

The demo assumes the SSH user, browser, and SIP softphone share one current
public IPv4 address. Discover it locally and provide it as `/32`.

STUN is outbound browser traffic. It does not require an EC2 STUN listener and
does not relay media. Browser and SIP media terminate at RTPEngine on UDP
`30000-30039`.

If a VPN, ISP, mobile network, or office network changes the public address,
update the CloudFormation CIDR parameters. Do not solve reachability by changing
ingress to `0.0.0.0/0`.

An external SIP provider may send RTP from addresses other than the workstation
CIDR. Add only documented provider CIDRs after validating them with the provider.
