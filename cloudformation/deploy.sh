#!/usr/bin/env bash
# Deploy the three stacks in order. Idempotent (uses `cloudformation deploy`).
#
#   cp cloudformation/deploy.env.example cloudformation/deploy.env   # fill in, never commit
#   ./cloudformation/deploy.sh network
#   ./cloudformation/deploy.sh data
#   (build + push the image: see .github/workflows/build-conductor.yml or docs/runbook.md)
#   IMAGE=<ecr-uri:tag> ./cloudformation/deploy.sh paperclip
#   ./cloudformation/deploy.sh all          # everything that has its inputs
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
env_file="${DEPLOY_ENV_FILE:-$here/deploy.env}"
if [ -f "$env_file" ]; then
  # shellcheck disable=SC1090
  set -a; . "$env_file"; set +a
fi

: "${AWS_REGION:=eu-central-1}"
: "${NAME:=aidlc}"
export AWS_REGION

stack() { printf '%s-%s' "$NAME" "$1"; }

deploy_network() {
  aws cloudformation deploy \
    --stack-name "$(stack network)" \
    --template-file "$here/10-network.yaml" \
    --parameter-overrides "Name=$NAME" "VpcCidr=${VPC_CIDR:-10.42.0.0/16}" \
    --no-fail-on-empty-changeset
}

deploy_data() {
  : "${GITHUB_APP_ID:?set in deploy.env}"
  : "${GITHUB_APP_INSTALLATION_ID:?set in deploy.env}"
  : "${GITHUB_APP_PRIVATE_KEY_FILE:?path to the .pem, set in deploy.env}"
  : "${ENTRA_CLIENT_SECRET:?set in deploy.env}"
  aws cloudformation deploy \
    --stack-name "$(stack data)" \
    --template-file "$here/20-data.yaml" \
    --parameter-overrides \
      "Name=$NAME" \
      "DbInstanceClass=${DB_INSTANCE_CLASS:-db.t4g.medium}" \
      "DbEngineVersion=${DB_ENGINE_VERSION:-17.9}" \
      "GitHubAppId=$GITHUB_APP_ID" \
      "GitHubAppInstallationId=$GITHUB_APP_INSTALLATION_ID" \
      "GitHubAppPrivateKeyPem=$(cat "$GITHUB_APP_PRIVATE_KEY_FILE")" \
      "EntraClientSecret=$ENTRA_CLIENT_SECRET" \
    --no-fail-on-empty-changeset
}

deploy_paperclip() {
  : "${IMAGE:?full ECR image URI incl. tag}"
  : "${DOMAIN:?set in deploy.env}"
  : "${ENTRA_TENANT_ID:?set in deploy.env}"
  : "${ENTRA_CLIENT_ID:?set in deploy.env}"
  aws cloudformation deploy \
    --stack-name "$(stack paperclip)" \
    --template-file "$here/30-paperclip.yaml" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      "Name=$NAME" \
      "Image=$IMAGE" \
      "Domain=$DOMAIN" \
      "HostedZoneId=${HOSTED_ZONE_ID:-}" \
      "EntraTenantId=$ENTRA_TENANT_ID" \
      "EntraClientId=$ENTRA_CLIENT_ID" \
      "DisableSignUp=${DISABLE_SIGN_UP:-false}" \
      "DesiredCount=${DESIRED_COUNT:-1}" \
      "BedrockPrimaryModel=${BEDROCK_PRIMARY_MODEL:-eu.anthropic.claude-opus-4-8-v1:0}" \
      "BedrockOpusModel=${BEDROCK_OPUS_MODEL:-eu.anthropic.claude-opus-4-8-v1:0}" \
      "BedrockSonnetModel=${BEDROCK_SONNET_MODEL:-eu.anthropic.claude-sonnet-4-6-v1:0}" \
      "BedrockHaikuModel=${BEDROCK_HAIKU_MODEL:-eu.anthropic.claude-haiku-4-6-v1:0}" \
      "WorkspaceRepoUrl=${WORKSPACE_REPO_URL:-https://github.com/navrang-aidlc-paperclip/aidlc-workspace.git}" \
      "GitHubActionsRepo=${GITHUB_ACTIONS_REPO:-navrang-aidlc-paperclip/aidlc-platform}" \
    --no-fail-on-empty-changeset
  aws cloudformation describe-stacks --stack-name "$(stack paperclip)" \
    --query 'Stacks[0].Outputs' --output table
}

case "${1:-all}" in
  network)   deploy_network ;;
  data)      deploy_data ;;
  paperclip) deploy_paperclip ;;
  all)       deploy_network; deploy_data; [ -n "${IMAGE:-}" ] && deploy_paperclip || echo "IMAGE not set; skipping paperclip stack" ;;
  *) echo "usage: $0 {network|data|paperclip|all}" >&2; exit 2 ;;
esac
