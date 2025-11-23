#!/bin/bash
set -e

STACK_NAME="claude-code-agent-stack"
REGION="ap-northeast-1"

echo "Retrieving API Key for AgentCore API Gateway..."
echo ""

# Get API Key ID from CloudFormation
API_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
    --output text)

if [ -z "$API_KEY_ID" ] || [ "$API_KEY_ID" = "None" ]; then
    echo "ERROR: Cannot get API Key ID. Run ./deploy_api.sh first."
    exit 1
fi

# Get API Key value
API_KEY_VALUE=$(aws apigateway get-api-key \
    --api-key "$API_KEY_ID" \
    --include-value \
    --region "$REGION" \
    --query 'value' \
    --output text)

echo "API Key ID: $API_KEY_ID"
echo "API Key Value: $API_KEY_VALUE"
echo ""
echo "Use this key in the x-api-key header:"
echo "curl -X POST <endpoint> -H 'x-api-key: $API_KEY_VALUE' -H 'Content-Type: application/json' -d '{...}'"
echo ""

# Save to file for test script
echo "$API_KEY_VALUE" > .api_key
echo "API Key saved to .api_key file"
