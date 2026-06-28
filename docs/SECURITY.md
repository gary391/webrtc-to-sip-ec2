# Security

- No default ingress uses `0.0.0.0/0`.
- IMDSv2 is required and the metadata hop limit is one.
- The root EBS volume is encrypted and deleted with the instance.
- MariaDB and RTPEngine control bind only to loopback.
- Kamailio authenticates local REGISTER/call traffic and rejects foreign relay.
- Nginx uses TLS 1.2/1.3 and proxies WebSocket only to loopback.
- Optional WebSocket ticket auth rejects missing, expired, reused, malformed,
  or wrong-scope tickets at Nginx before Kamailio sees the upgrade.
- TURN is disabled by default and anonymous relay is prohibited.
- `.env`, generated configuration, keys, and debug bundles are not committed.
- Debug collection redacts the database URL in Kamailio configuration.

Use unique generated SIP, database, and TURN passwords. Never place them in
CloudFormation, user data, outputs, GitHub, screenshots, or support bundles.

Optional later hardening includes fail2ban, Kamailio pike/htable rate limiting,
restricted provider CIDRs, and automated failed-authentication review.
