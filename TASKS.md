# Implementation Tasks

Status values: `TODO`, `IN PROGRESS`, `BLOCKED`, `DONE`.

| ID | Status | Task | Acceptance signal | Depends on |
|---|---|---|---|---|
| WTS-001 | DONE | Review the implementation spec and upstream project | Gaps and decisions recorded in `docs/SPEC_REVIEW.md` | - |
| WTS-002 | DONE | Scaffold the standalone implementation | Required top-level structure, task ledger, Makefile, and example environment exist | WTS-001 |
| WTS-003 | DONE | Build the locked-down CloudFormation baseline | Template resolves the latest Debian 13 AMI and creates one EC2 instance with no broad ingress, optional EIP/DNS, and required outputs | WTS-001 |
| WTS-004 | DONE | Implement environment validation | Invalid ICE combinations, default secrets, broad CIDRs, and reversed port ranges fail | WTS-002 |
| WTS-005 | DONE | Implement browser ICE configuration rendering | Tests cover STUN, none, valid TURN, and rejected TURN | WTS-004 |
| WTS-006 | DONE | Add EC2 metadata detection using IMDSv2 | Public/private IP, region, and instance ID are written without IMDSv1 fallback | WTS-002 |
| WTS-007 | DONE | Implement idempotent native package installation | Debian 13 baseline, Kamailio 6.1.3, and RTPEngine 13.5.1.16 installed on EC2; coturn remains optional | WTS-006 |
| WTS-008 | DONE | Implement MariaDB configuration | MariaDB 11.8.6 is loopback-only with the Kamailio schema and least-privilege DB user | WTS-007 |
| WTS-009 | DONE | Implement RTPEngine configuration | RTPEngine 13.5.1.16 is active with loopback control and the configured media range | WTS-007 |
| WTS-010 | DONE | Implement Kamailio configuration | Kamailio 6.1.3 parses and is active; authenticated registration, calling, media integration, and relay rejection still require end-to-end validation | WTS-008, WTS-009 |
| WTS-011 | DONE | Implement Nginx and TLS configuration | Browser-trusted IP certificate, HTTPS client root, `/ws` proxy configuration, external HTTP 200, and modern TLS are active | WTS-010 |
| WTS-012 | TODO | Implement optional coturn fallback | Explicit opt-in, long-term credentials, separate small relay range, no open relay | WTS-007 |
| WTS-013 | DONE | Add service lifecycle and status scripts | EC2 configure/start/status flow succeeds for MariaDB, RTPEngine, Kamailio, and Nginx and respects disabled coturn | WTS-008, WTS-009, WTS-010, WTS-011 |
| WTS-014 | DONE | Add health checks and capture tooling | EC2 health checks pass for services, HTTPS, SIP/control listeners, and database binding constraints | WTS-013 |
| WTS-015 | DONE | Write deployment, security, cost, validation, troubleshooting, and cleanup docs | All documents required by the spec exist and agree with implementation | WTS-003, WTS-014 |
| WTS-016 | DONE | Run an AWS deployment smoke test | Stack reached `CREATE_COMPLETE` in `us-west-2`; SSH, IMDSv2, private GitHub checkout, package installation, and core services were validated | WTS-019 |
| WTS-017 | DONE | Validate the end-to-end two-way audio demo | Browser registration, SIP call, media, and teardown satisfy acceptance criteria | WTS-016 and a SIP test client |
| WTS-018 | DONE | Prepare the GitHub-based development workflow | Standalone private Git repository, green CI, iteration runbook, and implementation `RepoUrl` are ready | WTS-003 |
| WTS-019 | DONE | Complete infrastructure deployment preflight | Local tests, `cfn-lint`, GitHub CI, CIDRs, key pair, and AWS parameters are confirmed | WTS-018 |
| WTS-020 | DONE | Resolve browser-client distribution approach | Pinned JsSIP 3.13.8 browser bundle is vendored with npm integrity metadata, reproducible build command, and MIT license | WTS-001 |

## Tracking rule

Update this file in the same change that starts or completes a task. A task may
be marked `DONE` only when its acceptance signal has been checked.
