# Development Workflow

GitHub is the source of truth for both infrastructure and host configuration.
The EC2 instance is a disposable validation target, not an independent place to
maintain code.

## Repository

Planned location:

```text
https://github.com/gary391/webrtc-to-sip-ec2
```

The repository can be public because `.env` and generated configuration are
ignored. If it is private, use a read-only deploy key or interactive SSH agent
forwarding. Never put a GitHub token, private key, SIP password, TURN password,
or database password in CloudFormation parameters, outputs, user data, commits,
or GitHub Actions variables.

## Local development

```bash
git switch main
git pull --ff-only
make test
```

Create a branch, make the change, and run the complete local test suite. Push
the branch and allow GitHub Actions to run `make test` and `cfn-lint` on Linux
amd64 before merging.

Apple Silicon is suitable for editing, template rendering, shell tests, and
CloudFormation validation. It cannot validate Debian package resolution,
systemd units, amd64 binaries, EC2 metadata, kernel behavior, security-group
reachability, or SIP/RTP media behavior. Those checks belong on the EC2 host.

## First EC2 checkout

CloudFormation keeps `CloneRepoOnBoot=false` by default. After the stack reaches
`CREATE_COMPLETE`, connect through SSH and clone interactively:

```bash
sudo install -d -o admin -g admin /opt/webrtc-to-sip
git clone https://github.com/gary391/webrtc-to-sip-ec2.git \
  /opt/webrtc-to-sip/source
cd /opt/webrtc-to-sip/source
make test
```

For a private repository, replace the HTTPS clone with the approved read-only
authentication method. Do not disable host-key checking or embed credentials in
the clone URL.

## Iteration loop

1. Reproduce and collect logs on EC2.
2. Make the fix in the local Git checkout, not directly in `/etc` on EC2.
3. Run `make test` locally and push the branch.
4. Merge only after CI succeeds.
5. On EC2, run `git pull --ff-only` from the clean `main` checkout.
6. Re-run the relevant configure target and runtime validation.
7. Record the result in `TASKS.md` or the validation documentation.

Emergency EC2 edits may be used to prove a diagnosis, but must be discarded and
reimplemented in Git before continuing. A dirty EC2 checkout is not a valid test
baseline.

## Infrastructure deployment gate

Infrastructure can be deployed before the full SIP call path is implemented.
The first stack is ready when:

- the implementation repository exists and GitHub CI is green
- local `make test` and `cfn-lint` pass
- the current public IP `/32`, EC2 key pair, AWS region, and domain plan are known
- the CloudFormation change set contains no unexpected resources or broad ingress
- the operator accepts `t3.medium`, EBS, and public IPv4 charges

Application readiness is a later gate covering package installation, service
configuration, SIP registration, signaling, media, and teardown.
