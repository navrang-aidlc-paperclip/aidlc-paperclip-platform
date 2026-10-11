#!/usr/bin/env bash
# PATH shim installed as `claude`. Paperclip's claude_local adapter execs this
# for every heartbeat; AI-DLC's hooks (children of the same process) inherit
# whatever we export here.
#
# The one rule that matters: AI-DLC only mints a HUMAN_TURN for a prompt that a
# person wrote. A Paperclip timer wake must therefore run with
# AIDLC_UNATTENDED=1 (gates stay closed), while a wake caused by a comment,
# assignment, approval, mention, or a finished specialist child is a turn
# that may open a gate and must NOT set it. A finished child is not a person:
# the conductor skill must not record it as an answer.
#
# Paperclip exposes the cause of the wake in PAPERCLIP_WAKE_REASON (plus
# PAPERCLIP_WAKE_COMMENT_ID / PAPERCLIP_WAKE_PAYLOAD_JSON). Treat anything we
# do not recognise as unattended: failing closed is the safe default.
set -euo pipefail

reason="${PAPERCLIP_WAKE_REASON:-heartbeat_timer}"
case "$reason" in
  issue_commented|issue_comment|comment|mention|issue_assigned|assignment|approval|approval_requested|approval_resolved|manual|on_demand|issue_children_completed|issue_blockers_resolved)
    unset AIDLC_UNATTENDED
    ;;
  *)
    export AIDLC_UNATTENDED=1
    ;;
esac

# Operator override for debugging only.
if [ -n "${AIDLC_FORCE_UNATTENDED:-}" ]; then
  export AIDLC_UNATTENDED="$AIDLC_FORCE_UNATTENDED"
fi

# Bedrock requires an explicit region. On ECS the task role supplies
# credentials through the container endpoint, and those tokens expire after
# about six hours. awsCredentialExport (managed settings, and the user
# settings written below) reloads them before Expiration. A static key left
# in the environment would shadow that endpoint and stay expired.
export CLAUDE_CODE_USE_BEDROCK="${CLAUDE_CODE_USE_BEDROCK:-1}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"

if [ -n "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI:-}${AWS_CONTAINER_CREDENTIALS_FULL_URI:-}" ]; then
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_BEARER_TOKEN_BEDROCK
  python3 - /usr/local/bin/ecs-task-credentials <<'PY'
import json, os, sys
from pathlib import Path

script = sys.argv[1]
targets = []
config = os.environ.get("CLAUDE_CONFIG_DIR")
if config:
    targets.append(Path(config) / "settings.json")
home = os.environ.get("HOME")
if home:
    targets.append(Path(home) / ".claude" / "settings.json")
for path in targets:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {}
        if path.exists():
            data = json.loads(path.read_text())
            if not isinstance(data, dict):
                continue
        if data.get("awsCredentialExport") == script:
            continue
        data["awsCredentialExport"] = script
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(data, indent=2) + "\n")
        tmp.replace(path)
    except Exception:
        pass
PY
fi

exec /usr/local/bin/claude-real "$@"
