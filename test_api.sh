#!/bin/bash
set -e

STACK_NAME="claude-code-agent-stack"
REGION="ap-northeast-1"

# Get API endpoint from CloudFormation
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

if [ -z "$API_ENDPOINT" ]; then
    echo "ERROR: Cannot get API endpoint. Run ./deploy_api.sh first."
    exit 1
fi

# Get API Key from file or retrieve it
if [ -f .api_key ]; then
    API_KEY=$(cat .api_key)
else
    echo "API Key not found in .api_key file. Retrieving..."
    ./get_api_key.sh > /dev/null 2>&1
    API_KEY=$(cat .api_key)
fi

if [ -z "$API_KEY" ]; then
    echo "ERROR: Cannot get API Key. Run ./get_api_key.sh first."
    exit 1
fi

# Get prompt from command line argument or use default
PROMPT="${1:-Create a hello world Python script}"

echo "API Endpoint: $API_ENDPOINT"
echo "Prompt: $PROMPT"
echo ""
echo "Invoking AgentCore via API Gateway..."
echo ""

# Invoke API with curl
curl -X POST "$API_ENDPOINT" \
    -H "x-api-key: $API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"prompt\": \"$PROMPT\"}" \
    | jq '.'

echo ""
