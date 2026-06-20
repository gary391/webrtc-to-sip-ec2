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
| WTS-007 | IN PROGRESS | Implement idempotent native package installation | Debian 13 baseline, latest Kamailio 6.1.x, and latest stable RTPEngine 13.5.x packages install; coturn remains optional | WTS-006 |
| WTS-008 | IN PROGRESS | Implement MariaDB configuration | Loopback-only DB, Kamailio schema, and least-privilege DB user | WTS-007 |
| WTS-009 | IN PROGRESS | Implement RTPEngine configuration | Latest reviewed 13.5.x release, loopback control, public advertised IP, and configured 30000-30039 default range | WTS-007 |
| WTS-010 | IN PROGRESS | Implement Kamailio configuration | Authenticated REGISTER/INVITE, WSS support, RTPEngine integration, and no open relay | WTS-008, WTS-009 |
| WTS-011 | IN PROGRESS | Implement Nginx and TLS configuration | HTTPS client and `/ws` proxy work with modern TLS | WTS-010 |
| WTS-012 | TODO | Implement optional coturn fallback | Explicit opt-in, long-term credentials, separate small relay range, no open relay | WTS-007 |
| WTS-013 | IN PROGRESS | Add service lifecycle and status scripts | Configure/start/stop/restart/status targets are repeatable | WTS-008, WTS-009, WTS-010, WTS-011 |
| WTS-014 | IN PROGRESS | Add health checks and capture tooling | Signaling, listeners, RTP range, and relevant journals are collected | WTS-013 |
| WTS-015 | DONE | Write deployment, security, cost, validation, troubleshooting, and cleanup docs | All documents required by the spec exist and agree with implementation | WTS-003, WTS-014 |
| WTS-016 | IN PROGRESS | Run an AWS deployment smoke test | Stack reaches `CREATE_COMPLETE` in `us-west-2` using `kamailio-course` and locked-down `/32` ingress | WTS-019 |
| WTS-017 | BLOCKED | Validate the end-to-end two-way audio demo | Browser registration, SIP call, media, and teardown satisfy acceptance criteria | WTS-016 and a SIP test client |
| WTS-018 | DONE | Prepare the GitHub-based development workflow | Standalone private Git repository, green CI, iteration runbook, and implementation `RepoUrl` are ready | WTS-003 |
| WTS-019 | DONE | Complete infrastructure deployment preflight | Local tests, `cfn-lint`, GitHub CI, CIDRs, key pair, and AWS parameters are confirmed | WTS-018 |
| WTS-020 | TODO | Resolve browser-client distribution approach | Client is legally redistributable or fetched from an explicitly approved source | WTS-001 |

## Tracking rule

Update this file in the same change that starts or completes a task. A task may
be marked `DONE` only when its acceptance signal has been checked.
