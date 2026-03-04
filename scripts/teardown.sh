#!/usr/bin/env bash
# teardown.sh — Deletes all AWS resources created by deploy.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/.deploy-state"

FUNCTION_NAME="card-trick-predict"
ROLE_NAME="card-trick-lambda-role"
API_NAME="card-trick-api"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[teardown]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}     $*"; }
die()  { echo -e "${RED}[error]${NC}    $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || die "aws CLI not found"

# ---------------------------------------------------------------------------
# Load state or fall back to querying by name
# ---------------------------------------------------------------------------
if [ -f "$STATE_FILE" ]; then
  log "Loading state from $STATE_FILE"
  # shellcheck source=/dev/null
  source "$STATE_FILE"
else
  warn "No state file found — querying AWS by resource names"
  REGION=$(aws configure get region 2>/dev/null || true)
  [ -z "$REGION" ] && die "Could not determine AWS region"
fi

echo ""
echo -e "${RED}This will permanently delete:${NC}"
echo "  - Lambda function: $FUNCTION_NAME"
echo "  - IAM role: $ROLE_NAME (+ attached policies)"
if [ -n "${API_ID:-}" ] && [ "$API_ID" != "None" ]; then
  echo "  - API Gateway HTTP API: $API_ID ($API_NAME)"
else
  echo "  - API Gateway HTTP API: $API_NAME (will look up ID)"
fi
echo "  - Lambda zip: $REPO_ROOT/card-trick-lambda.zip"
echo "  - $REPO_ROOT/lambda/node_modules"
echo ""
read -rp "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { log "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# API Gateway
# ---------------------------------------------------------------------------
if [ -z "${API_ID:-}" ] || [ "$API_ID" = "None" ]; then
  API_ID=$(aws apigatewayv2 get-apis \
    --query "Items[?Name=='$API_NAME'].ApiId | [0]" \
    --output text 2>/dev/null || true)
fi

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  log "Deleting API Gateway: $API_ID"
  aws apigatewayv2 delete-api --api-id "$API_ID" && log "API deleted" \
    || warn "Could not delete API (may already be gone)"
else
  warn "No API Gateway found with name '$API_NAME'"
fi

# ---------------------------------------------------------------------------
# Lambda function (also removes resource policies)
# ---------------------------------------------------------------------------
if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  log "Deleting Lambda function: $FUNCTION_NAME"
  aws lambda delete-function --function-name "$FUNCTION_NAME"
  log "Lambda deleted"
else
  warn "Lambda '$FUNCTION_NAME' not found — skipping"
fi

# ---------------------------------------------------------------------------
# IAM role (must detach all policies before deletion)
# ---------------------------------------------------------------------------
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  log "Detaching managed policies from role: $ROLE_NAME"
  ATTACHED=$(aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --query 'AttachedPolicies[*].PolicyArn' --output text)
  for ARN in $ATTACHED; do
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$ARN"
    log "  Detached: $ARN"
  done

  log "Deleting inline policies from role: $ROLE_NAME"
  INLINE=$(aws iam list-role-policies \
    --role-name "$ROLE_NAME" \
    --query 'PolicyNames[*]' --output text)
  for PNAME in $INLINE; do
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$PNAME"
    log "  Deleted inline policy: $PNAME"
  done

  log "Deleting IAM role: $ROLE_NAME"
  aws iam delete-role --role-name "$ROLE_NAME"
  log "Role deleted"
else
  warn "IAM role '$ROLE_NAME' not found — skipping"
fi

# ---------------------------------------------------------------------------
# Local artifacts
# ---------------------------------------------------------------------------
ZIP="$REPO_ROOT/card-trick-lambda.zip"
if [ -f "$ZIP" ]; then
  rm -f "$ZIP"
  log "Deleted $ZIP"
fi

MODULES="$REPO_ROOT/lambda/node_modules"
if [ -d "$MODULES" ]; then
  rm -rf "$MODULES"
  log "Deleted $MODULES"
fi

# Restore voice.html placeholder
PLACEHOLDER='https://YOUR_GATEWAY_ID.execute-api.REGION.amazonaws.com/predict'
sed -i "s|const API_ENDPOINT = \".*\";|const API_ENDPOINT = \"$PLACEHOLDER\";|" \
  "$REPO_ROOT/voice.html" 2>/dev/null && log "Restored voice.html placeholder"

# Remove state file
rm -f "$STATE_FILE" && log "Removed state file"

echo ""
echo -e "${GREEN}Teardown complete.${NC}"
echo ""
