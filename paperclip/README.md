# Paperclip configuration

Everything here is applied **after** `cloudformation/deploy.sh paperclip` has
produced a running Paperclip at `https://<DOMAIN>`. Paperclip keeps this state in
Postgres; the files in this folder are the source we import from so the setup
is reproducible.

## 1. First sign-in and lockdown

1. Open the URL; the ALB has already authenticated you with Entra ID. Create
   the first Paperclip account with the same e-mail (it becomes Owner).
2. Create the company `AI-DLC` (or your org name).
3. Redeploy with `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` (variable
   `paperclip_disable_sign_up = true`) so only invited users can join.

## 2. Users and roles

| Who | Paperclip role | Why |
| --- | --- | --- |
| You / platform owners | Owner or Admin | Agents, secrets, projects |
| Every stakeholder in `aidlc/stakeholders.yaml` | **Viewer** | They act only through per-issue execution policies set by the conductor |
| Optional auditors | Viewer + grant `audit:view_agent_actions` | Read the run log |

Invite each stakeholder with the exact e-mail used in `stakeholders.yaml`.

## 3. Secrets

Create these in Paperclip (Settings -> Secrets). Values are the same ones
you put in `cloudformation/deploy.env` (also stored in Secrets Manager under
`aidlc/github-app/*` by the data stack).

| Secret name | Value |
| --- | --- |
| `github-app-id` | GitHub App id |
| `github-app-installation-id` | Installation id on org `navrang-aidlc-paperclip` |
| `github-app-private-key` | PEM |

## 4. Project

Create project **aidlc-workspace** bound to
`https://github.com/navrang-aidlc-paperclip/aidlc-workspace`. Enable the
Documents and Artifacts tabs. Add a project **Document upload target** of
`aidlc/spaces/default/knowledge/documents/` so uploads land where
`/aidlc knowledge sync` indexes them.

## 5. Agent

Import `agents/aidlc-conductor.json`, replace the `${BEDROCK_*}` placeholders
with the paperclip stack's `BedrockModelIds` output, then click **Test Environment**. It
must report: `claude` found, cwd exists, a successful hello probe. The probe
goes through Bedrock with the task role; if it fails with `AccessDenied`,
model access is not enabled in the account for that model in `eu-central-1`.

Add the skill from `../conductor/skills/aidlc-conductor/SKILL.md` to the
agent (Agents -> aidlc-conductor -> Skills -> Add from file).

## 6. Issue template

Create an issue template **AI-DLC workflow** with:

- Title: `<what to build>`
- Body: the request in prose, optional links to uploaded documents
- Labels: `scope:<name>` (optional), `aidlc`
- Default assignee: `aidlc-conductor`
- Default execution policy: participants = requester + platform owners
  (the conductor widens it per stage)

## 7. Smoke run

1. Upload a one-paragraph vision doc to the project's Documents.
2. Create an issue from the template: "Build a hello-world HTTP service in
   svc-a", label `scope:poc`.
3. Expect within one heartbeat: a comment "Intent ... created", then the
   intent-capture questions, then issue status `Waiting on human`.
4. Answer as the product owner; approve. Expect the gate to open and the
   next stage's questions.
5. Answer as a Viewer who is **not** in the stage's roles: Paperclip must
   return 422 (not a participant). If a participant outside the answer roles
   comments, the conductor must record it as a note, not an answer.

This smoke run is the first checklist item in the master plan (gating seam).
