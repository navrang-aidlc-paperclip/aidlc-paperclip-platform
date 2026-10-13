# Paperclip configuration

Everything here is applied **after** `cloudformation/deploy.sh paperclip` has
produced a running Paperclip at `https://<DOMAIN>`. Paperclip keeps this state in
Postgres; the files in this folder are the source we import from so the setup
is reproducible.

## 1. First sign-in and lockdown

1. Open the URL and create the first Paperclip account (it becomes Owner).
   The pilot has no company login in front of the board, so this account is
   the only gate. Use the same e-mail you put in `aidlc/stakeholders.yaml`.
2. Create the company `AI-DLC` (or your org name).
3. Redeploy with `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` (variable
   `paperclip_disable_sign_up = true`) so only invited users can join.

## 2. Users and roles

| Who | Paperclip role | Why |
| --- | --- | --- |
| You / platform owners | Owner or Admin | Agents, secrets, projects |
| Every stakeholder in `aidlc/stakeholders.yaml` | **Viewer** | They act only through per-issue execution policies set by the conductor |
| Optional auditors | Viewer + grant `audit:view_agent_actions` | Read the run log |

Create those accounts from the stakeholders file. The command signs each distinct
e-mail up, and with a board API key also joins them as Viewer:

```sh
paperclip/bin/provision-stakeholders \
  --stakeholders /path/to/aidlc/stakeholders.yaml \
  --url https://<board> \
  --api-key "$PAPERCLIP_API_KEY"
```

The key is a Paperclip board API key for an Owner or Admin. Without it the
accounts are created and still have to be invited from the company menu.

## 3. Secrets

Create these in Paperclip (Settings -> Secrets). Values are the same ones
you put in `cloudformation/deploy.env` (also stored in Secrets Manager under
`aidlc/github-app/*` by the data stack).

| Secret name | Value |
| --- | --- |
| `github-app-id` | GitHub App id |
| `github-app-installation-id` | Installation id on org `navrang-aidlc-paperclip` |
| `github-app-private-key` | PEM |

## 4. Projects

Create one Paperclip project per AI-DLC effort. Nothing here is created for
you, and the image does not clone a repository on startup.

For each project:

1. Create the git repository and install the GitHub App on it.
2. In Paperclip, create a project and add a workspace with that repository's
   HTTPS URL and branch `main`. You choose the cwd in that form. Put it on
   the `/paperclip` volume so the checkout survives a new task. The workspace
   belongs to the project, not to the agent.
3. Enable the Documents and Artifacts tabs. Add a **Document upload target**
   of `aidlc/spaces/default/knowledge/documents/` so uploads land where
   `/aidlc knowledge sync` indexes them.

Repeat for every project. The same conductor agent serves all of them; the
issue's project workspace is its working directory. Set the project's
primary execution workspace to the record checkout with concurrency
`serialize`. Paperclip then keeps a second run off that tree until the
one already writing it has finished.

That primary checkout is the workflow record. Independent Construction
units do not build in it. When a batch starts, the conductor adds one
non-primary workspace per unit worktree, with `cwd` set to the path
`aidlc engine swarm prepare` prints, also `serialize`. Those worktrees
are different directories, so their builds run together. A second child
on the same worktree waits. A multi-repo intent keeps source in the
siblings from `repos.json`; one batch is one sibling, and `prepare` and
`finalize` still take turns on the record checkout. Design stages stay
on the primary checkout, one specialist at a time.

## 5. Agents

The conductor, the fourteen specialists, and the initializer are one
roster. Install them together. This creates the company skills and every
employee, and it is safe to run again.

```sh
export BEDROCK_PRIMARY_MODEL=...   # paperclip stack output BedrockModelIds
export BEDROCK_OPUS_MODEL=...
export BEDROCK_SONNET_MODEL=...
export BEDROCK_HAIKU_MODEL=...
paperclip/bin/provision-agents \
  --url https://<board> \
  --api-key "$PAPERCLIP_API_KEY"
```

The key is a Paperclip board API key for an Owner or Admin. The company
must already exist. Pass `--company` when the key can see more than one.

Each employee's `name` stays the slug the conductor assigns
(`aidlc-architect-agent`). The board title is the AI-DLC label
(`AI-DLC architect`). Paperclip's `role` is an org-chart enum (`engineer`,
`pm`, `qa`, ...); the title is the label people read. Specialists report
to the conductor. Leave every working directory empty so an issue uses its
project workspace.

`aidlc-conductor` is the only employee with a heartbeat, and the only
assignee on the workflow template. On that employee, click **Test
Environment**. It must report `claude` found, and a successful hello probe.
The probe goes through Bedrock with the task role; if it fails with
`AccessDenied`, model access is not enabled in the account for that model
in `eu-central-1`.

The other fourteen employees are the specialists in `.claude/agents/`.
Confirm in the UI that each has **no scheduled heartbeat**. A timer must
not start one. They wake only when the conductor assigns a child issue.
`aidlc-initializer` also has no heartbeat. It is not a specialist. A
person assigns it a task on a project that already has repositories
attached. It asks which repository holds the AI-DLC files and which
hold source (those can be the same repository), which release to
install, who holds each stakeholder role, and the vision and intent.
It writes `repos.json`, installs that release, writes
`aidlc/stakeholders.yaml`, and pushes. It does not start an intent.
`aidlc-composer-agent` is on the roster so it matches `.claude/agents`;
the conductor does not assign it. Compose stays in the conductor session.

| Employee | Skill |
| --- | --- |
| `aidlc-conductor` | `aidlc-conductor` |
| `aidlc-initializer` | `aidlc-initializer` |
| every `aidlc-*-agent` | `aidlc-specialist` |

## 6. Issue template

Create an issue template **AI-DLC workflow** with:

- Title: `<what to build>`
- Body: the request in prose, optional links to uploaded documents
- Labels: `scope:<name>` (optional), `aidlc`
- Default assignee: `aidlc-conductor`
- No stage gate on the template. The conductor opens a task ending in
  `:approve` for the approver at each gate. The Execution tab names that
  approver. There is no Approve card.

## 7. Smoke run

1. Upload a one-paragraph vision doc to the project's Documents.
2. Create an issue on that project from the template: "Build a hello-world
   HTTP service", label `scope:poc`. This is the **request**. It is the
   only issue the conductor runs AI-DLC on, and it stays assigned to the
   conductor until the intent is finished.
3. Expect within one heartbeat: a comment "Intent ... created" on the
   request, a goal on it, a document `AI-DLC progress` on it, the record
   committed and pushed, and only then a task `1.1-intent-capture:ask`.
   The conductor creates that task assigned to itself, blocks the request
   on it, and stops. A second run, bound to the ask task, posts the
   question card there and reassigns the task to the product owner (the
   first `answers` role in `stakeholders.yaml`). The request never carries
   the question card. Its description names the stage's answers, approver,
   and reviewer from `stakeholders.yaml`.
4. Answer the card on the ask task as that user, then set the task to
   **Done**. Expect the request to wake (`issue_blockers_resolved`),
   record the answers, and open `1.1-intent-capture:approve`. The review
   markdown (`intent-statement`) is a document on the request. The approve
   task's Execution tab names the approver from `stakeholders.yaml`. A
   stage whose `reviewer` is set shows that reviewer as the first stage on
   the same tab. There is no Approve card.
5. As the approver, set the task to **Done**. That is the approval. A
   comment is not required, and the status control cannot attach one.
   Expect the task to be `done`
   immediately, then the request to leave `blocked`, resume AI-DLC, and
   either open the next `:ask` or `:approve` task or assign a specialist
   child (`<number>-<slug>:<seq>:<agent>:<role>`) under the request. Another
   board user cannot complete the stage.
6. Request changes: set the status to **In progress**. Do not also set
   Done. A comment can explain the reason. The conductor closes
   the task, redoes the stage, and opens a fresh `:approve` task.
7. A Viewer who is not an addressee cannot submit a question card (403).
   An ordinary comment on a task is not an answer; the conductor replies
   once that answers go on the card. A comment that says "approve" does
   not open the gate.
8. Forgetting Done on an answered question card, or on an approval whose
   execution stage is already completed, is closed by the conductor's
   30-minute timer sweep. A stage that is still pending is not.

This project is one intent. Issue titles do not repeat the record directory.
There are no `stage:` or `unit:` issues any more; a stage shows up on the
board only when it needs a person (`2.3-requirements-analysis:ask`,
`2.3-requirements-analysis:approve`) or a specialist
(`3.5-code-generation:1:aidlc-developer-agent:lead`). Progress for the whole intent is the `AI-DLC progress`
document on the request.

This smoke run is the first checklist item in the master plan (gating seam).
