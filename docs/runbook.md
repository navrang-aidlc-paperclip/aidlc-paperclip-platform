# Runbook: from empty account to first gated run

Order matters; each step produces an input for the next.

## 0. Prerequisites (one-off)

- AWS account with Bedrock enabled in `eu-central-1`; request model access
  for the Anthropic models (Bedrock console → Model access). Confirm:
  `aws bedrock list-inference-profiles --region eu-central-1 --query 'inferenceProfileSummaries[].inferenceProfileId'`
  and put the real ids into `deploy.env` (`BEDROCK_*_MODEL`).
- Entra ID app registration: Web platform, redirect URI
  `https://<DOMAIN>/oauth2/idpresponse`, ID tokens enabled, a client secret.
  Note tenant id, client id, secret.
- GitHub App: see `github-app.md`.
- GitHub repos created and pushed: `aidlc-workspace`, `aidlc-platform`,
  `svc-a`, `svc-b` (empty source repos are fine; `main` must exist).
- Locally: AWS CLI v2, Docker (for a manual first build), `jq`.

## 1. Network and data stacks

```bash
cp cloudformation/deploy.env.example cloudformation/deploy.env   # fill in
./cloudformation/deploy.sh network
./cloudformation/deploy.sh data      # ~10 min (RDS)
```

## 2. First conductor image

The GitHub Actions workflow needs the `ImagePushRole` which lives in the
paperclip stack, which needs an image. Break the cycle with one manual build:

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REPO=$ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/aidlc-conductor
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin "$REPO"
docker buildx build --platform linux/amd64 \
  --build-arg AIDLC_VERSION=$(cat ../aidlc-workspace/.aidlc-version) \
  -t "$REPO:2.11.0-manual" --push conductor/
```

## 3. Paperclip stack

```bash
IMAGE=$REPO:2.11.0-manual ./cloudformation/deploy.sh paperclip
```

If `HOSTED_ZONE_ID` was empty: create the ACM DNS validation CNAME (ACM
console) and a CNAME `DOMAIN → LoadBalancerDnsName` output. The stack waits
on certificate validation.

Then: put the `ImagePushRoleArn` output into the `aidlc-platform` GitHub repo
as Actions variable `AWS_IMAGE_PUSH_ROLE_ARN`. Future image builds run from
`.github/workflows/build-conductor.yml`.

## 4. Verify the container

```bash
TASK=$(aws ecs list-tasks --cluster aidlc-paperclip --service-name aidlc-paperclip --query 'taskArns[0]' --output text)
aws ecs execute-command --cluster aidlc-paperclip --task "$TASK" --container paperclip --interactive --command bash
# inside:
aidlc --version                       # 2.11.0
claude --version                      # wrapper -> real
ls /paperclip/workspaces/aidlc-workspace/.claude   # bootstrap cloned the workspace
cd /paperclip/workspaces/aidlc-workspace && aidlc doctor
PAPERCLIP_WAKE_REASON=issue_commented claude -p "say hello" --output-format text   # Bedrock round-trip through the task role
```

Expected `aidlc doctor` state: everything ok except `Providers:
bedrock-model-access pending` until the bootstrap can `get-inference-profile`
on `ANTHROPIC_MODEL` (then it marks it done itself).

## 5. Paperclip configuration

Follow `../paperclip/README.md` (sign-in, roles, secrets, project, agent,
issue template). Finish with the **smoke run** described there; it is the
gating-seam check from the master plan:

1. comment wake → `claude` wrapper leaves `AIDLC_UNATTENDED` unset →
   `UserPromptSubmit` hook records `HUMAN_TURN` → gate can open
2. timer wake → `AIDLC_UNATTENDED=1` → gate stays closed
3. non-participant comment → Paperclip 422
4. participant outside the stage's answer roles → recorded as a note

If (1) fails (no `HUMAN_TURN` in `audit/` after a comment wake), the
headless `claude -p` path is not firing `UserPromptSubmit`; the fallback is
to have the conductor call `aidlc engine hook record-human-turn` explicitly
at the start of a human-originated wake. Record what you observe in the
master-plan checklist before changing anything.

## 6. Day-2

| Task | How |
| --- | --- |
| New AI-DLC release | bump `.aidlc-version` in aidlc-workspace, run `aidlc config` there, commit; rebuild image with the same `AIDLC_VERSION`; deploy |
| New Paperclip release | `workflow_dispatch` with `paperclip_tag`; validate on a copy before `latest` |
| Add a source repo | add to `repos.json`, install the GitHub App on it, next wake clones it |
| Scale to zero overnight | `DESIRED_COUNT=0 ./cloudformation/deploy.sh paperclip` (EFS keeps state) |
| Costs | Bedrock usage via Cost Explorer filter `Service=Amazon Bedrock`; set a budget alarm; Paperclip per-agent budgets in the UI |
| Logs | CloudWatch `/ecs/aidlc-paperclip`; run logs in the S3 bucket; audit in `aidlc/spaces/*/intents/*/audit/` |
