# Cost Guardrails

The baseline uses one on-demand `t3.medium`, one 30 GiB gp3 root volume, and one
public IPv4 address. Public IPv4 addresses are billed while allocated, including
Elastic IPs associated with running instances. `t3.medium` may not be free-tier
eligible.

The stack intentionally excludes NAT Gateway, load balancers, RDS, EFS,
autoscaling, WAF, managed TURN, and paid observability.

Before deployment, check current regional EC2, EBS, public IPv4, Route 53, and
data-transfer pricing in the AWS calculator. Configure a small billing budget.
Stop the instance between short tests if preserving its disk is useful; delete
the stack and release the EIP when the demo is finished.
