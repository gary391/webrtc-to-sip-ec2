# AWS CloudFormation Deployment

Do not create the stack until `make deploy-readiness` passes and the deployment
commit has green GitHub CI.

## Inputs

1. Choose the AWS region and confirm an EC2 key pair exists there.
2. From the workstation that will run the browser, SSH, and SIP client:

   ```bash
   curl -s https://checkip.amazonaws.com
   ```

3. Append `/32` for `AdminCidr`. For `DemoClientCidr`, use the narrowest CIDR that still covers the browser and SIP endpoint; `/32` is preferred, but a broader range such as `136.226.0.0/15` is acceptable when the SIP/media source address changes across the provider network.
4. Decide whether to use an Elastic IP. Keep the default `true` when DNS is
   deferred or when an IP-address certificate may be used.
5. Decide how TLS will be provisioned. A domain is not required to create the
   stack, but the browser demo requires a trusted HTTPS origin for microphone
   access. DNS-01 remains the preferred locked-down option.

Let's Encrypt can issue short-lived IP-address certificates, so a domain is no
longer an absolute requirement for the demo. These certificates are valid for
about six days and require Certbot 5.4 or newer for the documented webroot flow.
They also require temporary public ACME validation reachability. Use a stable
Elastic IP, automate renewal, and close the temporary validation rule after
issuance. A domain with DNS-01 is operationally simpler and does not require
opening HTTP validation access.

## Confirmed first-deployment inputs

```text
AWS region: us-west-2
KeyPairName: <key>
AdminCidr: <IP-Address>
DemoClientCidr: <IP-Address>
UseElasticIp: true
HostedZoneId: <blank>
DomainName: <blank>
CloneRepoOnBoot: false
EnableSipUdp: true
EnableSipTcp: false
EnableHttp: false
EnableTurn: false
```

The CIDRs represent the current public addresses used by the workstation and
SIP/media path. If the ISP, VPN, or carrier NAT changes them, update the
parameters before reconnecting; CloudFormation will update the security group
without replacing the instance.

## Create the stack

1. Open CloudFormation in the selected region and choose **Create stack**.
2. Upload `infra/cloudformation/webrtc-to-sip-ec2.yaml`.
3. Select the EC2 key pair and enter the two `/32` CIDRs.
4. Keep Debian, `t3.medium`, gp3, standard CPU credits, STUN, and TURN defaults.
5. Keep `CloneRepoOnBoot=false` for the first deployment.
6. Review the change set. It should contain one VPC, subnet, route table, internet
   gateway, security group, EC2 instance, role/profile, and optional EIP/DNS record.
7. Reject the change set if it contains broad ingress or unexpected managed services.
8. Create the stack and wait for `CREATE_COMPLETE`.

Save the stack outputs, especially `InstancePublicIp`, `SshCommand`,
`VsCodeRemoteSshHostSnippet`, and `NextStepsPath`.

## First connection

Verify SSH, then clone the implementation repository interactively as documented
in `DEVELOPMENT_WORKFLOW.md`. Do not install services until the checkout is clean
and `make test` passes on EC2.
