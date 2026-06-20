# AWS CloudFormation Deployment

Do not create the stack until `make deploy-readiness` passes and the deployment
commit has green GitHub CI.

## Inputs

1. Choose the AWS region and confirm an EC2 key pair exists there.
2. From the workstation that will run the browser, SSH, and SIP client:

   ```bash
   curl -s https://checkip.amazonaws.com
   ```

3. Append `/32` and use it for both `AdminCidr` and `DemoClientCidr`.
4. Decide whether to use an Elastic IP. The default is `true` for stable DNS.
5. Decide how TLS will be provisioned. DNS-01 is preferred when Route 53 is available.

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
