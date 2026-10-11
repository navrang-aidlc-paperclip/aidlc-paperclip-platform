# aidlc-platform

Everything needed to run AI-DLC cloud-natively on AWS: Paperclip as the
shared board, Claude Code on Amazon Bedrock as the conductor, no laptops, no
local clones. This repository is only the board. Each AI-DLC project is
added later as its own Paperclip project, bound to its own git repository.

```
cloudformation/
  10-network.yaml        VPC, subnets, NAT, VPC endpoints (Bedrock, Secrets Manager, ECR, Logs, STS, S3), SGs
  20-data.yaml           RDS Postgres 17, EFS (/paperclip), S3 run logs, ECR, all secrets
  30-paperclip.yaml      ECS Fargate service, ALB + ACM, IAM (Bedrock task role), GitHub OIDC push role
  deploy.sh              deploys the stacks in order from deploy.env
conductor/
  Dockerfile             ghcr.io/paperclipai/paperclip + pinned aidlc + AWS CLI + glue
  bin/aidlc-entrypoint.sh        hand off to the Paperclip entrypoint; clones nothing
  bin/aidlc-prepare-project      pin and doctor the project checkout for this wake
  bin/claude-wrapper.sh          sets AIDLC_UNATTENDED from PAPERCLIP_WAKE_REASON, forces Bedrock env
  bin/ecs-task-credentials       reloads the ECS task-role token before it expires
  bin/git-credential-github-app  short-lived GitHub App installation tokens for git
  skills/aidlc-conductor/SKILL.md  board behaviour, including specialist assignment
  skills/aidlc-specialist/SKILL.md one brief, one output file, then stop
paperclip/
  agents/                        conductor + fourteen specialist definitions
  bin/provision-agents           install that roster and both skills on a board
  README.md                      roles, secrets, project, agents, issue template, smoke run
docs/
  runbook.md             empty account → first gated run, day-2 ops
  github-app.md          the GitHub App the conductor authenticates with
.github/workflows/build-conductor.yml   build + push the image to ECR (OIDC), optional rollout
```

## Architecture (pilot)

```
Browser ──▶ ALB ──▶ ECS Fargate task "aidlc-paperclip"
                            ├─ paperclip-server (UI, API, heartbeat scheduler)
                            └─ claude (conductor and specialist employees, claude_local)
                                 ├─ /aidlc skill + hooks from the project checkout for this issue
                                 ├─ Bedrock (task role, VPC endpoint)         ── model calls
                                 └─ GitHub (App token)                         ── whichever project repos the board is given
                            volume: EFS /paperclip  (instance config, sessions; project checkouts go here when you add them)
                            data:   RDS Postgres     (Paperclip state)
                            logs:   CloudWatch + S3  (run logs)
```

Paperclip's `claude_local` adapter spawns `claude` inside the server
container; that is why the conductor is baked into the same image. Moving it
to a separate sandbox (Paperclip Kubernetes provider on EKS) is a later
hardening step. Project repositories stay outside this image either way.

## Start here

`docs/runbook.md`.
