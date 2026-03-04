#!/usr/bin/env bash
# deploy.sh — Packages and deploys the card-trick voice Lambda + API Gateway.
# Safe to re-run: existing resources are reused/updated rather than recreated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/.deploy-state"

FUNCTION_NAME="card-trick-predict"
ROLE_NAME="card-trick-lambda-role"
API_NAME="card-trick-api"
MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
ZIP_PATH="$REPO_ROOT/card-trick-lambda.zip"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC}   $*"; }
die()  { echo -e "${RED}[error]${NC}  $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
command -v aws >/dev/null 2>&1 || die "aws CLI not found — install it first"
command -v zip >/dev/null 2>&1 || die "zip not found"

# Activate Node.js 20 via nvm and force its bin dir to the front of PATH.
# This is necessary because other package managers (e.g. Homebrew node@18) may
# appear earlier in PATH and shadow the nvm-managed node even after `nvm use`.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  \. "$NVM_DIR/nvm.sh"
  nvm use 20 2>/dev/null || nvm use --lts 2>/dev/null || true
  _nvm_bin="$(nvm which 20 2>/dev/null | xargs dirname 2>/dev/null || true)"
  [ -n "$_nvm_bin" ] && export PATH="$_nvm_bin:$PATH"
fi

command -v npm >/dev/null 2>&1 || die "npm not found"
NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 20 ]; then
  die "Node.js 20+ required (current: $(node --version 2>/dev/null || echo 'none')). Run: nvm install 20"
fi
log "Node.js $(node --version)"

REGION=$(aws configure get region 2>/dev/null || true)
if [ -z "$REGION" ]; then
  REGION=$(aws ec2 describe-availability-zones \
    --query 'AvailabilityZones[0].RegionName' --output text 2>/dev/null || true)
fi
[ -z "$REGION" ] && die "Could not determine AWS region. Run: aws configure"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "Region: $REGION | Account: $ACCOUNT_ID"

# ---------------------------------------------------------------------------
# Step 1: Package Lambda
# ---------------------------------------------------------------------------
log "Installing Lambda dependencies..."
cd "$REPO_ROOT/lambda"
npm install --omit=dev --quiet

log "Creating zip: $ZIP_PATH"
zip -r "$ZIP_PATH" . --quiet
cd "$REPO_ROOT"
log "Package size: $(du -sh "$ZIP_PATH" | cut -f1)"

# ---------------------------------------------------------------------------
# Step 2: IAM role
# ---------------------------------------------------------------------------
log "Checking IAM role: $ROLE_NAME"
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  log "Role already exists — using it"
  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text)
else
  log "Creating IAM role..."
  TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  ROLE_ARN=$(aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --query Role.Arn --output text)
  log "Created role: $ROLE_ARN"
fi

log "Attaching policies..."
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  2>/dev/null || true   # already attached is fine

BEDROCK_POLICY=$(cat <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["bedrock:InvokeModel", "bedrock:Converse"],
    "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
  }]
}
POLICY
)
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name BedrockHaikuAccess \
  --policy-document "$BEDROCK_POLICY"

log "Waiting 10 s for IAM role to propagate..."
sleep 10

# ---------------------------------------------------------------------------
# Step 3: Lambda function
# ---------------------------------------------------------------------------
ENV_VARS="Variables={MODEL_ID=$MODEL_ID}"

if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
  log "Lambda exists — updating code and config..."
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --query 'FunctionArn' --output text >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME"
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --role "$ROLE_ARN" \
    --timeout 30 \
    --memory-size 256 \
    --environment "$ENV_VARS" \
    --query 'FunctionArn' --output text >/dev/null
  aws lambda wait function-updated --function-name "$FUNCTION_NAME"
else
  log "Creating Lambda function..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime nodejs20.x \
    --handler index.handler \
    --role "$ROLE_ARN" \
    --zip-file "fileb://$ZIP_PATH" \
    --timeout 30 \
    --memory-size 256 \
    --environment "$ENV_VARS" \
    --query 'FunctionArn' --output text >/dev/null
  aws lambda wait function-active --function-name "$FUNCTION_NAME"
fi

LAMBDA_ARN=$(aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --query Configuration.FunctionArn --output text)
log "Lambda ARN: $LAMBDA_ARN"

# ---------------------------------------------------------------------------
# Step 4: API Gateway HTTP API
# ---------------------------------------------------------------------------
EXISTING_API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='$API_NAME'].ApiId | [0]" \
  --output text 2>/dev/null || true)

if [ -z "$EXISTING_API_ID" ] || [ "$EXISTING_API_ID" = "None" ]; then
  log "Creating API Gateway HTTP API..."
  # No API-level CORS config — Lambda handles CORS headers directly.
  # This avoids API Gateway intercepting OPTIONS preflights and dropping
  # the Access-Control-Allow-Origin header for null/file:// origins.
  API_ID=$(aws apigatewayv2 create-api \
    --name "$API_NAME" \
    --protocol-type HTTP \
    --query ApiId --output text)
  log "Created API: $API_ID"

  log "Creating Lambda integration..."
  INTEGRATION_ID=$(aws apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "$LAMBDA_ARN" \
    --payload-format-version 2.0 \
    --query IntegrationId --output text)

  log "Creating POST /predict route..."
  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "POST /predict" \
    --target "integrations/$INTEGRATION_ID" \
    --query RouteId --output text >/dev/null

  log "Creating OPTIONS /predict route..."
  aws apigatewayv2 create-route \
    --api-id "$API_ID" \
    --route-key "OPTIONS /predict" \
    --target "integrations/$INTEGRATION_ID" \
    --query RouteId --output text >/dev/null

  log "Creating auto-deploy stage..."
  aws apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name '$default' \
    --auto-deploy \
    --query StageName --output text >/dev/null
else
  API_ID="$EXISTING_API_ID"
  log "API Gateway already exists: $API_ID"

  # Ensure OPTIONS /predict route exists (may be missing on older deploys)
  EXISTING_OPTIONS=$(aws apigatewayv2 get-routes \
    --api-id "$API_ID" \
    --query "Items[?RouteKey=='OPTIONS /predict'].RouteId | [0]" \
    --output text 2>/dev/null || true)
  if [ -z "$EXISTING_OPTIONS" ] || [ "$EXISTING_OPTIONS" = "None" ]; then
    log "Adding missing OPTIONS /predict route..."
    INTEGRATION_ID=$(aws apigatewayv2 get-integrations \
      --api-id "$API_ID" \
      --query 'Items[0].IntegrationId' --output text)
    aws apigatewayv2 create-route \
      --api-id "$API_ID" \
      --route-key "OPTIONS /predict" \
      --target "integrations/$INTEGRATION_ID" \
      --query RouteId --output text >/dev/null
  fi
fi

# ---------------------------------------------------------------------------
# Step 5: Lambda invoke permission for API Gateway
# ---------------------------------------------------------------------------
log "Setting Lambda resource policy..."
aws lambda remove-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id allow-apigw \
  2>/dev/null || true
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id allow-apigw \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/predict" \
  --query Statement --output text >/dev/null

# ---------------------------------------------------------------------------
# Step 6: Get invoke URL and patch voice.html
# ---------------------------------------------------------------------------
INVOKE_URL=$(aws apigatewayv2 get-api \
  --api-id "$API_ID" \
  --query ApiEndpoint --output text)
ENDPOINT="${INVOKE_URL}/predict"

log "Patching voice.html with endpoint: $ENDPOINT"
sed -i "s|const API_ENDPOINT = \".*\";|const API_ENDPOINT = \"$ENDPOINT\";|" \
  "$REPO_ROOT/voice.html"

# ---------------------------------------------------------------------------
# Step 7: Save state for teardown
# ---------------------------------------------------------------------------
cat > "$STATE_FILE" <<STATE
FUNCTION_NAME=$FUNCTION_NAME
ROLE_NAME=$ROLE_NAME
API_ID=$API_ID
REGION=$REGION
ACCOUNT_ID=$ACCOUNT_ID
INVOKE_URL=$INVOKE_URL
STATE
log "State saved to $STATE_FILE"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Deploy complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  API endpoint: $ENDPOINT"
echo ""
echo "  Test with:"
echo "    curl -X POST $ENDPOINT \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"transcript\":\"Ace of spades, three of hearts, jack of clubs, seven of diamonds\"}'"
echo ""
warn "ACTION REQUIRED: Enable Bedrock model access if you haven't already."
warn "  1. Open: https://console.aws.amazon.com/bedrock/home?region=$REGION#/modelaccess"
warn "  2. Click 'Manage model access'"
warn "  3. Check 'Claude 3 Haiku' and save"
echo ""
