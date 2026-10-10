# syntax=docker/dockerfile:1.6
#
# Paperclip server + AI-DLC conductor, one image.
#
# Pilot topology (ECS Fargate): Paperclip's `claude_local` adapter runs `claude`
# as a child process of paperclip-server, so the harness, the pinned `aidlc`
# runtime, git and the GitHub-App credential helper all have to be in the same
# container as the server. Moving the conductor into its own sandbox task
# (Paperclip Kubernetes/Daytona providers) is a later hardening step and does
# not change anything in the aidlc-workspace repo.
#
# Upstream already ships: node 24, @anthropic-ai/claude-code, git, gh, jq,
# ripgrep, python3, tini, gosu, openssh-client. We add:
#   - the exact AI-DLC release the workspace pins (.aidlc-version)
#   - a `claude` PATH wrapper that derives AIDLC_UNATTENDED from the Paperclip
#     wake reason (timers never mint human turns, people do)
#   - a git credential helper that mints short-lived GitHub App tokens
#   - a workspace bootstrap that clones aidlc-workspace + repos.json siblings
#
# Build:  docker build --build-arg AIDLC_VERSION=2.11.0 -t aidlc-conductor conductor/
# Pin PAPERCLIP_TAG to a release tag once you have validated one; `latest`
# moves weekly.

ARG PAPERCLIP_TAG=latest
FROM ghcr.io/paperclipai/paperclip:${PAPERCLIP_TAG}

ARG AIDLC_VERSION=2.11.0
ARG TARGETARCH

USER root

# ---- AI-DLC native runtime (machine-wide, outside the volume) --------------
# The installer refuses to run as root, so it runs as the runtime user (node,
# uid 1000) into /opt/aidlc. That root also holds the machine-local pin
# registry (pins.json) the bootstrap writes, so node must own it. It lives in
# the image layer, not under /paperclip (an EFS mount at runtime). The hooks
# in .claude/settings.json call the bare `aidlc` command, so it must be on the
# system PATH for every process the adapter spawns: ENV PATH + a symlink.
ENV AIDLC_INSTALL_ROOT=/opt/aidlc \
    AIDLC_BIN_DIR=/opt/aidlc/bin \
    PATH=/opt/aidlc/bin:$PATH
RUN set -eux; \
    mkdir -p /opt/aidlc/bin && chown -R node:node /opt/aidlc; \
    gosu node sh -c ' \
      set -eu; tmp="$(mktemp -d)"; \
      curl -fsSL "https://github.com/awslabs/aidlc-workflows/releases/download/v'"${AIDLC_VERSION}"'/install.sh" -o "$tmp/install.sh"; \
      sh "$tmp/install.sh" --version "'"${AIDLC_VERSION}"'" --yes --quiet; \
      rm -rf "$tmp"'; \
    ln -s /opt/aidlc/bin/aidlc /usr/local/bin/aidlc; \
    aidlc --version

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
COPY bin/claude-wrapper.sh          /usr/local/bin/claude-wrapper
COPY bin/git-credential-github-app  /usr/local/bin/git-credential-github-app
COPY bin/aidlc-bootstrap-workspace  /usr/local/bin/aidlc-bootstrap-workspace
COPY bin/aidlc-entrypoint.sh        /usr/local/bin/aidlc-entrypoint.sh
RUN set -eux; \
    chmod +x /usr/local/bin/claude-wrapper /usr/local/bin/git-credential-github-app \
             /usr/local/bin/aidlc-bootstrap-workspace /usr/local/bin/aidlc-entrypoint.sh; \
    real="$(readlink -f "$(command -v claude)")"; \
    rm -f /usr/local/bin/claude; \
    ln -s "$real" /usr/local/bin/claude-real; \
    ln -s /usr/local/bin/claude-wrapper /usr/local/bin/claude; \
    claude --version

# Git identity for commits the conductor makes in the record repo and the
# source repos. Override per deployment with env.
ENV GIT_AUTHOR_NAME="aidlc-conductor" \
    GIT_AUTHOR_EMAIL="aidlc-conductor@users.noreply.github.com" \
    GIT_COMMITTER_NAME="aidlc-conductor" \
    GIT_COMMITTER_EMAIL="aidlc-conductor@users.noreply.github.com" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=credential.https://github.com.helper \
    GIT_CONFIG_VALUE_0=github-app \
    # Claude Code on Bedrock. AWS_REGION must be explicit; credentials come
    # from the ECS task role via the container credential provider.
    CLAUDE_CODE_USE_BEDROCK=1 \
    AWS_REGION=eu-central-1 \
    DISABLE_PROMPT_CACHING=0 \
    # Where the bootstrap puts the workspace (on the /paperclip volume so the
    # record survives task replacement; the Paperclip agent's cwd points here).
    AIDLC_WORKSPACES_ROOT=/paperclip/workspaces \
    AIDLC_WORKSPACE_REPO=https://github.com/navrang-aidlc-paperclip/aidlc-workspace.git \
    AIDLC_WORKSPACE_NAME=aidlc-workspace

# Upstream ENTRYPOINT is `tini -- docker-entrypoint.sh`; we insert our
# bootstrap in front of the upstream entrypoint and keep its CMD.
ENTRYPOINT ["/usr/bin/tini", "--", "aidlc-entrypoint.sh"]
