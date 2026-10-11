# Runbook: from empty account to first gated run

Order matters; each step produces an input for the next.

## 0. Prerequisites (one-off)

- AWS account with Bedrock enabled in `eu-central-1`; request model access
  for the Anthropic models (Bedrock console → Model access). Confirm:
  `aws bedrock list-inference-profiles --region eu-central-1 --query 'inferenceProfileSummaries[].inferenceProfileId'`
  and put the real ids into `deploy.env` (`BEDROCK_*_MODEL`).
- GitHub App: see `github-app.md`. The pilot app is `navrang-aidlc-conductor`,
  owned by the deploying user and installed on the organization.
- Board login for the pilot is a Paperclip account. No Entra app.
- This platform repo pushed. Project repositories are created when a
  project is added to the board, not as part of the image.
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
  -f conductor/Dockerfile \
  -t "$REPO:manual" --push .
```

## 3. Paperclip stack

```bash
IMAGE=$REPO:manual ./cloudformation/deploy.sh paperclip
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
ls /opt/aidlc/versions                # empty until a project wake installs its pin
claude --version                      # wrapper -> real
ls /paperclip                         # instance data only, until you add a project
PAPERCLIP_WAKE_REASON=issue_commented claude -p "say hello" --output-format text   # Bedrock round-trip through the task role
```

Task-role tokens expire after about six hours. Claude reloads them through
`awsCredentialExport` (`/usr/local/bin/ecs-task-credentials`) before that, so a
session can keep running. This is in the image: a task still on an older image
keeps the first token until it is replaced.

`aidlc doctor` runs later, inside a project checkout, from
`aidlc-prepare-project`. Until a project exists there is nothing to doctor.

## 5. Paperclip configuration

Follow `../paperclip/README.md` (sign-in, roles, secrets, project, agents,
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
| New AI-DLC release | change that project's `.aidlc-version`. The next wake installs that release. The image does not contain one |
| New Paperclip release | `workflow_dispatch` with `paperclip_tag`; validate on a copy before `latest` |
| Add a project | create its git repo, install the GitHub App on it, add a Paperclip project whose workspace points at that repo |
| Scale to zero overnight | `DESIRED_COUNT=0 ./cloudformation/deploy.sh paperclip` (EFS keeps state) |
| Costs | Bedrock usage via Cost Explorer filter `Service=Amazon Bedrock`; set a budget alarm; Paperclip per-agent budgets in the UI |
| Logs | CloudWatch `/ecs/aidlc-paperclip`; run logs in the S3 bucket; audit in `aidlc/spaces/*/intents/*/audit/` |
