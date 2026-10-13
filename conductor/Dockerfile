# syntax=docker/dockerfile:1.6
#
# Paperclip server + conductor glue, one image.
#
# Pilot topology (ECS Fargate): Paperclip's `claude_local` adapter runs `claude`
# as a child process of paperclip-server, so the harness, git and the GitHub-App
# credential helper have to be in the same container as the server. The AI-DLC
# engine is not in this image. `aidlc-prepare-project` installs the release named
# in that project's `.aidlc-version` the first time a checkout is prepared.
# Projects are attached in Paperclip, one repo per project. None of them are
# baked into this image.
#
# Upstream already ships: node 24, @anthropic-ai/claude-code, git, gh, jq,
# ripgrep, python3, tini, gosu, openssh-client. We add:
#   - an empty install root the prepare step fills from the project's pin
#   - a `claude` PATH wrapper that derives AIDLC_UNATTENDED from the Paperclip
#     wake reason (timers never mint human turns, people do)
#   - a git credential helper that mints short-lived GitHub App tokens
#   - a prepare step the conductor runs inside whichever project it was woken for
#
# Build from the platform repository root:
#   docker build -f conductor/Dockerfile -t aidlc-conductor .
# Pin PAPERCLIP_TAG to a release tag once you have validated one; `latest`
# moves weekly.

ARG PAPERCLIP_TAG=latest
FROM ghcr.io/paperclipai/paperclip:${PAPERCLIP_TAG}

ARG TARGETARCH

USER root

# Paperclip's ACP launcher forwards static AWS keys only. On Fargate the task
# role arrives as AWS_CONTAINER_CREDENTIALS_RELATIVE_URI. ecs-task-credentials
# reads that endpoint; dropping the URI here makes every Bedrock call fail.
RUN python3 - <<'PY'
from pathlib import Path
path = Path("/app/packages/adapter-utils/src/acpx-engine/execute.ts")
text = path.read_text()
needle = '"AWS_SHARED_CREDENTIALS_FILE"'
keys = (
    "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI",
    "AWS_CONTAINER_CREDENTIALS_FULL_URI",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN",
    "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE",
)
missing = [key for key in keys if key not in text]
if missing:
    idx = text.find(needle)
    if idx < 0:
        raise SystemExit("Claude ACP credential allowlist anchor is missing")
    line_start = text.rfind("\n", 0, idx) + 1
    indent = text[line_start:idx]
    line_end = text.find("\n", idx)
    extra = "".join(f'\n{indent}"{key}",' for key in missing)
    path.write_text(text[:line_end] + extra + text[line_end:])
PY

# Paperclip refuses an exclusive checkout lock for a local folder, then starts
# the next agent beside the one already writing it. A project policy of
# `serialize` must take the existing workspace-busy gate on this host too.
# `auto` and `allow` stay as upstream left them.
RUN python3 - <<'PY'
import re
from pathlib import Path
needle = 'sharedWorkspaceConcurrency !== "allow" &&'
insert = 'sharedWorkspaceConcurrency === "serialize" || sharedWorkspaceConcurrency !== "allow" &&'
comment = re.compile(
    r"Local/SSH folders never take an exclusive workspace lock, including when older\n"
    r"[ \t]*// project or issue settings request serialization\."
)
replacement = "serialize takes the exclusive lock on a local folder too. auto still leaves local and SSH folders unlocked."
files = (
    Path("/app/server/src/services/heartbeat.ts"),
    Path("/app/server/dist/services/heartbeat.js"),
)
for path in files:
    text = path.read_text()
    if text.count(needle) != 1 or len(comment.findall(text)) != 1:
        raise SystemExit(f"workspace lock anchor missing or duplicated in {path}")
    path.write_text(comment.sub(replacement, text, count=1).replace(needle, insert, 1))
PY

# The board status control and the comment box are separate requests. An
# execution stage must be completable by setting Done, without a comment in
# that same request. A comment left earlier is not that request.
RUN python3 - <<'PY'
import re
from pathlib import Path
approve_gate = re.compile(
    r"[ \t]*if \(!input\.commentBody\?\.trim\(\)\) \{\n"
    r"[ \t]*throw unprocessable\(`Approving a review or approval stage requires a comment\. \$\{STAGE_DECISION_COMMENT_HINT\}`\);\n"
    r"[ \t]*\}\n"
)
changes_gate = re.compile(
    r"[ \t]*if \(!input\.commentBody\?\.trim\(\)\) \{\n"
    r"[ \t]*throw unprocessable\(`Requesting changes requires a comment\. \$\{STAGE_DECISION_COMMENT_HINT\}`\);\n"
    r"[ \t]*\}\n"
)
body = re.compile(r"body: input\.commentBody\.trim\(\),")
files = (
    Path("/app/server/src/services/issue-execution-policy.ts"),
    Path("/app/server/dist/services/issue-execution-policy.js"),
)
for path in files:
    text = path.read_text()
    if len(approve_gate.findall(text)) != 1 or len(changes_gate.findall(text)) != 1 or len(body.findall(text)) != 3:
        raise SystemExit(f"execution comment gate anchor missing or duplicated in {path}")
    text = approve_gate.sub("", text, count=1)
    text = changes_gate.sub("", text, count=1)
    text = body.sub('body: input.commentBody?.trim() || "Approved",', text, count=2)
    text = body.sub('body: input.commentBody?.trim() || "Changes requested",', text, count=1)
    path.write_text(text)
PY

# ---- AI-DLC install root (empty until a project is prepared) ---------------
# The installer refuses to run as root. aidlc-prepare-project runs as node and
# fills this directory with the release named in the checkout's .aidlc-version.
# Hooks call the bare `aidlc` command, so the bin dir is on PATH. Nothing under
# /paperclip (the EFS mount) holds the binary. This layer does not download it.
ENV AIDLC_INSTALL_ROOT=/opt/aidlc \
    AIDLC_BIN_DIR=/opt/aidlc/bin \
    PATH=/opt/aidlc/bin:$PATH
RUN mkdir -p /opt/aidlc/bin && chown -R node:node /opt/aidlc

# ---- AWS CLI (Bedrock model-access checks, Secrets Manager, ECR) ----------
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      arm64) awsarch=aarch64 ;; \
      *)     awsarch=x86_64 ;; \
    esac; \
    apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awsarch}.zip" -o /tmp/awscli.zip; \
    unzip -q /tmp/awscli.zip -d /tmp; /tmp/aws/install; rm -rf /tmp/aws /tmp/awscli.zip; \
    aws --version

# ---- Conductor glue --------------------------------------------------------
# /usr/local/bin precedes npm's global bin (/usr/local/lib/node_modules/.bin is
# NOT on PATH; npm links into /usr/local/bin). Rename the real binary and put
# the wrapper where `claude` was so Paperclip's "Test Environment" and the
# adapter's exec both hit the wrapper.
# Build context is the platform repository root (see .github/workflows/build-conductor.yml).
COPY conductor/bin/claude-wrapper.sh          /usr/local/bin/claude-wrapper
COPY conductor/bin/ecs-task-credentials       /usr/local/bin/ecs-task-credentials
COPY conductor/bin/git-credential-github-app  /usr/local/bin/git-credential-github-app
COPY conductor/bin/aidlc-prepare-project      /usr/local/bin/aidlc-prepare-project
COPY conductor/bin/aidlc-entrypoint.sh        /usr/local/bin/aidlc-entrypoint.sh
COPY conductor/claude/managed-settings.json   /etc/claude-code/managed-settings.json
COPY conductor/skills                         /opt/conductor/paperclip-skills
COPY paperclip/agents                         /opt/conductor/paperclip-agents
COPY paperclip/bin/provision-agents           /usr/local/bin/provision-agents
RUN set -eux; \
    chmod +x /usr/local/bin/claude-wrapper /usr/local/bin/ecs-task-credentials \
             /usr/local/bin/git-credential-github-app \
             /usr/local/bin/aidlc-prepare-project /usr/local/bin/aidlc-entrypoint.sh \
             /usr/local/bin/provision-agents; \
    mkdir -p /home/node/.claude; \
    cp /etc/claude-code/managed-settings.json /home/node/.claude/settings.json; \
    chown -R node:node /home/node/.claude; \
    real="$(readlink -f "$(command -v claude)")"; \
    rm -f /usr/local/bin/claude; \
    ln -s "$real" /usr/local/bin/claude-real; \
    ln -s /usr/local/bin/claude-wrapper /usr/local/bin/claude; \
    ver="$(claude-real --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"; \
    VER="$ver" python3 -c 'import os,sys; v=tuple(int(x) for x in os.environ["VER"].split(".")); \
sys.exit(0 if v >= (2, 1, 206) else 1)'; \
    echo "claude $ver supports awsCredentialExport"

# Git identity for commits the conductor makes in a project checkout.
# Override per deployment with env.
ENV GIT_AUTHOR_NAME="aidlc-conductor" \
    GIT_AUTHOR_EMAIL="aidlc-conductor@users.noreply.github.com" \
    GIT_COMMITTER_NAME="aidlc-conductor" \
    GIT_COMMITTER_EMAIL="aidlc-conductor@users.noreply.github.com" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=credential.https://github.com.helper \
    GIT_CONFIG_VALUE_0=github-app \
    # Claude Code on Bedrock. AWS_REGION must be explicit. Task-role tokens
    # are reloaded by awsCredentialExport before they expire.
    CLAUDE_CODE_USE_BEDROCK=1 \
    AWS_REGION=eu-central-1 \
    DISABLE_PROMPT_CACHING=0

# Setting ENTRYPOINT clears the base image's CMD, so the server command has
# to be restated. docker-entrypoint.sh ends in `exec gosu node "$@"`.
ENTRYPOINT ["/usr/bin/tini", "--", "aidlc-entrypoint.sh"]
CMD ["node", "--import", "./server/node_modules/tsx/dist/loader.mjs", "server/dist/index.js"]
