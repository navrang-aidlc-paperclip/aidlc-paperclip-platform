# aidlc-platform

Everything needed to run AI-DLC cloud-natively on AWS: Paperclip as the
shared board, Claude Code on Amazon Bedrock as the conductor, no laptops, no
local clones. The AI-DLC materials themselves live in the sibling repo
`aidlc-workspace`; generated code lives in `svc-*` repos.

```
cloudformation/
  10-network.yaml        VPC, subnets, NAT, VPC endpoints (Bedrock, Secrets Manager, ECR, Logs, STS, S3), SGs
  20-data.yaml           RDS Postgres 17, EFS (/paperclip), S3 run logs, ECR, all secrets
  30-paperclip.yaml      ECS Fargate service, ALB + ACM + Entra ID OIDC, IAM (Bedrock task role), GitHub OIDC push role
  deploy.sh              deploys the stacks in order from deploy.env
conductor/
  Dockerfile             ghcr.io/paperclipai/paperclip + pinned aidlc + AWS CLI + glue
  bin/aidlc-entrypoint.sh        bootstrap workspace, then upstream entrypoint
  bin/aidlc-bootstrap-workspace  clone/refresh aidlc-workspace + repos.json siblings, aidlc doctor
  bin/claude-wrapper.sh          sets AIDLC_UNATTENDED from PAPERCLIP_WAKE_REASON, forces Bedrock env
  bin/git-credential-github-app  short-lived GitHub App installation tokens for git
  skills/aidlc-conductor/SKILL.md  the conductor's board behaviour and answer-provenance rules
paperclip/
  agents/aidlc-conductor.json    claude_local agent definition to import
  README.md                      roles, secrets, project, agent, issue template, smoke run
docs/
  runbook.md             empty account → first gated run, day-2 ops
  github-app.md          the GitHub App the conductor authenticates with
.github/workflows/build-conductor.yml   build + push the image to ECR (OIDC), optional rollout
```

## Architecture (pilot)

```
Entra ID ──OIDC──▶ ALB ──▶ ECS Fargate task "aidlc-paperclip"
                            ├─ paperclip-server (UI, API, heartbeat scheduler)
                            └─ claude (conductor, claude_local adapter, persistent sessions)
                                 ├─ /aidlc skill + hooks from aidlc-workspace/.claude
                                 ├─ Bedrock (task role, VPC endpoint)         ── model calls
                                 └─ GitHub (App token)                         ── aidlc-workspace, svc-*
                            volume: EFS /paperclip  (instance config, sessions, workspaces/)
                            data:   RDS Postgres     (Paperclip state)
                            logs:   CloudWatch + S3  (run logs)
```

Paperclip's `claude_local` adapter spawns `claude` inside the server
container; that is why the conductor is baked into the same image. Moving it
to a separate sandbox (Paperclip Kubernetes provider on EKS) is a later
hardening step that leaves `aidlc-workspace` untouched.

## Start here

`docs/runbook.md`.
