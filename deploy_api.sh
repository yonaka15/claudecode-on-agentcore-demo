#!/bin/bash
set -e

STACK_NAME="claude-code-agent-stack"
REGION="ap-northeast-1"

echo "========================================="
echo "Deploying API Gateway + Lambda for AgentCore"
echo "========================================="

# Get AgentCore runtime ARN from deployment.json
if [ ! -f deployment.json ]; then
    echo "ERROR: deployment.json not found. Run ./deploy.sh first to create AgentCore runtime."
    exit 1
fi

RUNTIME_ARN=$(jq -r '.runtime_arn' deployment.json)

if [ -z "$RUNTIME_ARN" ] || [ "$RUNTIME_ARN" = "null" ]; then
    echo "ERROR: Cannot extract runtime_arn from deployment.json"
    exit 1
fi

echo "Using AgentCore Runtime ARN: $RUNTIME_ARN"
echo ""

# Update CloudFormation stack with API Gateway parameter
echo "Updating CloudFormation stack with API Gateway resources..."
aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://infrastructure.yaml \
    --parameters ParameterKey=AgentCoreRuntimeArn,ParameterValue="$RUNTIME_ARN" \
    --capabilities CAPABILITY_IAM \
    --region "$REGION"

echo "Waiting for stack update to complete..."
aws cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

# Get API endpoint URL
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Get API Key
API_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
    --output text)

API_KEY_VALUE=$(aws apigateway get-api-key \
    --api-key "$API_KEY_ID" \
    --include-value \
    --region "$REGION" \
    --query 'value' \
    --output text)

# Save API Key to file
echo "$API_KEY_VALUE" > .api_key

echo ""
echo "========================================="
echo "API Gateway Deployment Complete!"
echo "========================================="
echo ""
echo "API Endpoint: $API_ENDPOINT"
echo "API Key: $API_KEY_VALUE"
echo ""
echo "API Key saved to .api_key file"
echo ""
echo "Test with curl:"
echo "curl -X POST $API_ENDPOINT \\"
echo "  -H 'x-api-key: $API_KEY_VALUE' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"prompt\": \"Create a hello world Python script\"}'"
echo ""
echo "Or use the test script:"
echo "./test_api.sh \"Create a hello world Python script\""
echo ""
