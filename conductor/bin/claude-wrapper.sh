#!/usr/bin/env bash
# PATH shim installed as `claude`. Paperclip's claude_local adapter execs this
# for every heartbeat; AI-DLC's hooks (children of the same process) inherit
# whatever we export here.
#
# The one rule that matters: AI-DLC only mints a HUMAN_TURN for a prompt that a
# person wrote. A Paperclip timer wake must therefore run with
# AIDLC_UNATTENDED=1 (gates stay closed), while a wake caused by a comment,
# assignment, approval or mention is a human turn and must NOT set it.
#
# Paperclip exposes the cause of the wake in PAPERCLIP_WAKE_REASON (plus
# PAPERCLIP_WAKE_COMMENT_ID / PAPERCLIP_WAKE_PAYLOAD_JSON). Treat anything we
# do not recognise as unattended: failing closed is the safe default.
set -euo pipefail

reason="${PAPERCLIP_WAKE_REASON:-heartbeat_timer}"
case "$reason" in
  issue_commented|issue_comment|comment|mention|issue_assigned|assignment|approval|approval_requested|approval_resolved|manual|on_demand)
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

# Bedrock requires an explicit region; the task role supplies credentials.
export CLAUDE_CODE_USE_BEDROCK="${CLAUDE_CODE_USE_BEDROCK:-1}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"

exec /usr/local/bin/claude-real "$@"
