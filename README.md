# Claude Code Agent on Amazon Bedrock AgentCore

Deploy Claude Code as an autonomous, serverless AI agent on AWS. Execute multi-step coding tasks via natural language prompts with automatic file generation and S3 storage.

> **Based on**: [aws-samples/anthropic-on-aws/claude-code-on-agentcore](https://github.com/aws-samples/anthropic-on-aws/tree/main/claude-code-on-agentcore)

## Features

- **Autonomous Execution**: Headless Claude Code operation without interactive UI
- **AWS-Native Integration**: Amazon Bedrock Haiku 4.5 (no Anthropic API keys required)
- **Serverless Architecture**: AgentCore runtime with automatic scaling
- **Dual Access Methods**: AWS CLI + HTTP API (curl-compatible)
- **API Key Authentication**: Secure API Gateway with rate limiting
- **File Management**: Automatic S3 upload with timestamped sessions
- **Single Command Deployment**: Unified deployment script

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Inbound Access (User → Agent)                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Method 1: AWS CLI                                                   │
│  ./invoke_claude_code.sh "task" → AgentCore Runtime                 │
│                                                                      │
│  Method 2: HTTP API (curl)                                          │
│  curl + API Key → API Gateway → Lambda → AgentCore Runtime          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ AgentCore Runtime                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  FastAPI Server → Claude Agent SDK → Bedrock (Haiku 4.5)            │
│       ↓                                                              │
│  File Operations → S3 (outputs/YYYYMMDD_HHMMSS/)                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Outbound Access (Agent → External Tools) [Optional]                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  AgentCore Runtime → AgentCore Gateway → External APIs              │
│                                           (Salesforce, Slack, etc)  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS Account with Bedrock access in `ap-northeast-1` (Tokyo)
- AWS CLI 2.32.1+ (`brew upgrade awscli`)
- Docker with buildx support
- AWS Marketplace subscription to Claude Haiku 4.5
- IAM permissions: Bedrock, CloudFormation, ECR, S3, IAM, Lambda, API Gateway

## Quick Start

### 1. Deploy Infrastructure and AgentCore Runtime

```bash
./deploy.sh
```

This script:
- Creates CloudFormation stack (IAM roles, S3 bucket, ECR repository)
- Builds ARM64 Docker image with Claude Code CLI
- Pushes image to ECR
- Deploys AgentCore runtime
- Saves configuration to `deployment.json`

### 2. Deploy API Gateway (Optional)

For curl-based HTTP access:

```bash
./deploy_api.sh
```

This adds:
- Lambda function for AgentCore invocation
- API Gateway REST API with `/invoke` endpoint
- API Key authentication with rate limiting
- CORS support

## Usage

### Method 1: AWS CLI (Direct)

```bash
./invoke_claude_code.sh "Create a hello world Python script"
```

### Method 2: HTTP API (curl)

```bash
# Using test script (automatic API Key handling)
./test_api.sh "Create a FastAPI server with health check endpoint"

# Or curl directly
API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name claude-code-agent-stack \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text)

API_KEY=$(cat .api_key)

curl -X POST "$API_ENDPOINT" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a REST API for user management",
    "permission_mode": "acceptEdits",
    "allowed_tools": "Bash,Read,Write,Replace,Search,List"
  }'
```

### Request Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `prompt` | string | Yes | - | Natural language task description |
| `permission_mode` | string | No | `acceptEdits` | `acceptEdits`, `acceptAll`, or `manual` |
| `allowed_tools` | string | No | All tools | Comma-separated tool names |

### Response Format

```json
{
  "output": {
    "success": true,
    "result": "Task completion message",
    "session_id": "uuid",
    "timestamp": "2025-11-23T09:02:52.339528",
    "model": "claude-haiku-4.5",
    "metadata": {
      "duration_ms": 2753,
      "num_turns": 2,
      "uploaded_files": [
        {
          "file_name": "app.py",
          "s3_url": "s3://bucket/outputs/20251123_090252/app.py",
          "console_url": "https://s3.console.aws.amazon.com/..."
        }
      ]
    }
  }
}
```

## Management Commands

```bash
# View deployment info
./show_agent_info.sh

# Download generated files from S3
./download_outputs.sh

# Get API Key
./get_api_key.sh

# View AgentCore logs
aws logs tail /aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT --follow

# View Lambda logs
aws logs tail /aws/lambda/claude-code-agent-api --follow
```

## Project Structure

```
.
├── agent.py                  # FastAPI server (AgentCore entrypoint)
├── infrastructure.yaml       # CloudFormation template
├── Dockerfile               # ARM64 container image
├── deploy.sh                # Unified deployment script
├── deploy_api.sh            # API Gateway deployment
├── invoke_claude_code.sh    # AWS CLI invocation script
├── test_api.sh              # HTTP API test script
├── get_api_key.sh           # API Key retrieval
├── show_agent_info.sh       # Display deployment info
├── download_outputs.sh      # Download S3 files
├── deployment.json          # Runtime metadata (generated)
├── .api_key                 # API Key (generated, git-ignored)
└── pyproject.toml           # Python dependencies
```

## Infrastructure Components

### CloudFormation Resources

- **OutputBucket**: S3 bucket for generated files (30-day lifecycle)
- **EcrRepository**: Docker image repository (keeps last 5 images)
- **AgentCoreExecutionRole**: IAM role with Bedrock, S3, CloudFront permissions
- **LambdaExecutionRole**: IAM role for API Gateway Lambda
- **AgentCoreLambda**: Lambda function (Python 3.12, 900s timeout, 512MB memory)
- **AgentCoreApi**: API Gateway REST API
- **ApiKey**: Auto-generated API key
- **ApiUsagePlan**: Rate limiting (10 req/sec, burst 20, daily quota 1000)

### AgentCore Runtime

- **Image**: ARM64 Docker with Node.js 20+ and Python 3.12
- **Model**: Claude Haiku 4.5 (`jp.anthropic.claude-haiku-4-5-20251001-v1:0`)
- **Region**: ap-northeast-1 (Tokyo)
- **Working Directory**: `/app/workspace` (isolated execution environment)

## Security

### API Key Authentication

- Required header: `x-api-key: <api-key-value>`
- Stored in `.api_key` file (git-ignored)
- Retrieve via `./get_api_key.sh`
- Rotate by deleting API Key resource and redeploying

### Rate Limiting

- 10 requests/second
- Burst: 20 requests
- Daily quota: 1000 requests

### IAM Permissions

**AgentCore Execution Role**:
- `bedrock:InvokeModel` (Claude Haiku 4.5)
- `s3:PutObject`, `s3:GetObject` (OutputBucket)
- `aws-marketplace:ViewSubscriptions`, `aws-marketplace:Subscribe`

**Lambda Execution Role**:
- `bedrock-agentcore:InvokeAgentRuntime`
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

## Cost Estimation

**Monthly cost for moderate usage (1000 requests)**:

| Service | Cost |
|---------|------|
| Claude Haiku 4.5 | $0.25 (input) + $1.25 (output) ≈ $1.50 |
| AgentCore Runtime | $0.10 (1000 invocations) |
| API Gateway | $0.0035 (1000 requests) |
| Lambda | $0.20 (1000 invocations × 3s × 512MB) |
| S3 | $0.023 (1GB storage) |
| **Total** | **~$2.03/month** |

## Troubleshooting

### Lambda Environment Variable Error

**Error**: `AWS_REGION is a reserved environment variable`

**Solution**: Remove `AWS_REGION` from Lambda environment variables. boto3 auto-detects region from Lambda execution context.

### boto3 Client Error

**Error**: `Missing required parameter: agentAliasId, agentId`

**Solution**: Use correct service name:
```python
# Wrong
client = boto3.client('bedrock-agent-runtime')

# Correct
client = boto3.client('bedrock-agentcore')
response = client.invoke_agent_runtime(...)
```

### IAM Permission Error

**Error**: `User is not authorized to perform: bedrock-agentcore:InvokeAgentRuntime`

**Solution**: Update Lambda IAM role:
```yaml
Action:
  - bedrock-agentcore:InvokeAgentRuntime  # Not bedrock-agent-runtime:InvokeAgent
```

### API Key 403 Forbidden

**Error**: `{"message":"Forbidden"}`

**Solution**: Include `x-api-key` header with valid API key from `.api_key` file.

### Marketplace Subscription

**Error**: `403 AccessDeniedException` when invoking model

**Solution**:
1. Add `AWSMarketplaceFullAccess` to IAM user
2. Update CloudFormation with Marketplace permissions
3. Wait 10 minutes for IAM propagation
4. Invoke model once via Bedrock Console Playground
5. Redeploy AgentCore runtime

## Advanced Topics

### Permission Modes

- **acceptEdits** (default): Auto-approve file edits, prompt for other operations
- **acceptAll**: Fully autonomous (auto-approve all tool uses)
- **manual**: Prompt for every tool use (not recommended for headless)

### Custom Tool Configuration

Override allowed tools:
```json
{
  "prompt": "Your task",
  "allowed_tools": "Bash,Read,Write,Replace"
}
```

### S3 Upload Behavior

- Triggers only after successful execution (`success: true`)
- Scans `/app/workspace` recursively
- Creates timestamped prefix: `outputs/YYYYMMDD_HHMMSS/`

### Using AgentCore Gateway (Optional)

For agent-to-external-tool communication:

```bash
# Create Gateway for external tool integration
aws bedrock-agentcore create-gateway \
  --gateway-name slack-gateway \
  --targets '[{"type":"REST_API","openapi_spec":"slack-openapi.json"}]'

# Update agent.py to use Gateway
# (Implementation depends on use case)
```

**Note**: AgentCore Gateway is for **outbound** access (agent → external tools), not for inbound access (user → agent). This project implements inbound access via API Gateway + Lambda.

## References

- [AWS Sample Repository](https://github.com/aws-samples/anthropic-on-aws/tree/main/claude-code-on-agentcore)
- [Amazon Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/)
- [Claude Agent SDK](https://github.com/anthropics/claude-code)
- [AgentCore Gateway Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway.html)
