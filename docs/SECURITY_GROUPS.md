# Security Groups

Default ingress:

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | `AdminCidr` | SSH |
| 443 | TCP | `DemoClientCidr` | HTTPS and WSS |
| 5060 | UDP | `DemoClientCidr` | SIP test client |
| 30000-30039 | UDP | `DemoClientCidr` | RTPEngine media |

TCP 5060 and HTTP 80 are conditional. TURN 3478 TCP/UDP and relay UDP
31000-31039 exist only when `EnableTurn=true`. MariaDB 3306 and RTPEngine control
22222 must never have security-group ingress rules.

Outbound access remains open for package repositories, GitHub, DNS, STUN, and
normal SIP/media responses. This does not weaken the inbound restrictions.
