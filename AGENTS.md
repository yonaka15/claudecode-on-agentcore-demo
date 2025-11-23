# AgentCore Demo - Claude Code on Amazon Bedrock

FastAPI service that runs Claude Code headless on Amazon Bedrock AgentCore. Accepts natural language prompts, executes autonomous coding tasks, uploads generated files to S3.

## Architecture

- **agent.py**: FastAPI server exposing `/invocations` endpoint
- **Claude Agent SDK**: Headless Claude Code execution via `query()` async iterator
- **Amazon Bedrock**: Model inference (Claude Haiku 4.5)
- **S3**: Generated file storage with timestamped prefixes
- **Docker**: ARM64 container with Node.js (Claude Code CLI) + Python (FastAPI)
- **CloudFormation**: IAM role, S3 bucket, ECR repository
- **API Gateway + Lambda**: HTTP endpoint for curl-based invocation (optional)

## Critical Guardrails

- **Regional model access**: Haiku 4.5 uses region-specific inference profiles → Use `jp.anthropic.claude-haiku-4-5-20251001-v1:0` for ap-northeast-1, not `global.*`
- **Marketplace permissions required**: IAM role MUST have `aws-marketplace:ViewSubscriptions` and `aws-marketplace:Subscribe` → First invocation triggers Marketplace subscription
- **First-time model activation**: Invoke model once via Bedrock Console Playground or API to complete Marketplace subscription → 403 errors persist until subscription completes
- **Permission propagation delay**: After adding Marketplace permissions, wait 10 minutes before retrying → IAM changes are eventually consistent
- **Working directory isolation**: Agent always executes in `/app/workspace` container directory → Files created here are uploaded to S3
- **Bedrock environment variables**: Must set `CLAUDE_CODE_USE_BEDROCK=1` and `AWS_REGION` in both Docker ENV and ClaudeAgentOptions.env → Missing either breaks model inference
- **ARM64 platform**: Docker build MUST use `--platform linux/arm64` → AgentCore only supports ARM64
- **Runtime naming**: AgentCore runtime names match `[a-zA-Z][a-zA-Z0-9_]{0,47}` → Replace hyphens with underscores (deploy.sh:142)
- **ECR login timing**: Always run `aws ecr get-login-password` before Docker push → Credentials expire after 12 hours
- **AWS CLI version**: Requires AWS CLI 2.32.1+ for `bedrock-agentcore` commands → Upgrade with `brew upgrade awscli`
- **Lambda reserved env vars**: Cannot use `AWS_REGION` in Lambda env vars → boto3 auto-detects region from execution context
- **Lambda IAM permissions**: Must use `bedrock-agentcore:InvokeAgentRuntime`, not `bedrock-agent-runtime:InvokeAgent` → Different service namespaces

## Core Workflow (Deployment)

1. **Deploy infrastructure**: `./deploy.sh` runs full pipeline (CloudFormation → Docker build → AgentCore runtime)
2. **Verify stack outputs**: Script extracts Role ARN, S3 bucket, ECR URI from CloudFormation
3. **Build Docker image**: Uses buildx for ARM64, passes OUTPUT_BUCKET_NAME as build arg
4. **Deploy AgentCore runtime**: Python script creates/updates runtime, saves `deployment.json`

## Core Workflow (Invocation)

### Method 1: Direct AgentCore (AWS CLI)

1. **Invoke agent**: `./invoke_claude_code.sh "Create a hello world app"`
2. **Agent execution**: FastAPI receives prompt → calls `query()` → iterates messages → extracts text
3. **File upload**: After successful execution, scans `/app/workspace` → uploads to S3 with timestamp prefix
4. **Response format**: Returns JSON with result text, session metadata, uploaded file URLs

### Method 2: API Gateway (curl)

1. **Deploy API**: `./deploy_api.sh` (one-time setup)
2. **Invoke via HTTP**: `./test_api.sh "Create a hello world app"` or use curl directly
3. **Lambda execution**: API Gateway → Lambda → AgentCore → Response
4. **Response format**: Same JSON format as direct invocation

## Common Operations

**View deployment info:**
```bash
./show_agent_info.sh  # Displays runtime ARN, S3 bucket, region
```

**Download generated files:**
```bash
./download_outputs.sh  # Lists S3 sessions, prompts for selection, downloads to local ./outputs/
```

**Deploy API Gateway (optional):**
```bash
./deploy_api.sh  # One-time setup for curl-based access
```

**Invoke via curl:**
```bash
./test_api.sh "Create a Python hello world script"

# Or use curl directly with API Key
API_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name claude-code-agent-stack \
  --region ap-northeast-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text)

API_KEY=$(cat .api_key)

curl -X POST "$API_ENDPOINT" \
  -H "x-api-key: $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "Create a hello world app"}'
```

**Get API Key:**
```bash
./get_api_key.sh  # Retrieves and displays API Key, saves to .api_key file
```

**Manual AWS CLI invocation:**
```bash
# Encode payload as base64
echo -n '{"input":{"prompt":"Your task"}}' | base64

# Invoke runtime
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn <arn> \
  --region ap-northeast-1 \
  --payload <base64> \
  response.json
```

## Agent SDK Message Flow

```python
async for message in query(prompt, options):
    if isinstance(message, SystemMessage):
        # Informational (log only)
    elif isinstance(message, AssistantMessage):
        # Extract TextBlock content for response
    elif isinstance(message, ResultMessage):
        # Final message: session_id, duration_ms, num_turns
```

**Key points:**
- `query()` returns async iterator → Use `async for` loop
- `AssistantMessage.content` is list of blocks → Filter for TextBlock instances
- `ResultMessage` marks end → Extract metadata here
- System messages are informational → No action needed

## Permission Modes

Configurable via `permission_mode` input parameter:

- **acceptEdits** (default): Auto-approve file edits, ask for other operations
- **acceptAll**: Auto-approve all tool uses (fully autonomous)
- **manual**: Prompt for every tool use (not recommended for headless)

## Allowed Tools

Default tools for autonomous operation:
```
Bash,Read,Write,Replace,Search,List,WebFetch,AskFollowup
```

Override via `allowed_tools` input parameter (comma-separated).

## S3 Upload Behavior

**Automatic upload triggers:**
- Only after successful execution (`result.success == True`)
- Scans `/app/workspace` recursively for all files
- Creates session prefix: `outputs/YYYYMMDD_HHMMSS/`

**Upload metadata format:**
```json
{
  "file_name": "relative/path.txt",
  "s3_url": "s3://bucket/outputs/20241123_164500/relative/path.txt",
  "console_url": "https://s3.console.aws.amazon.com/..."
}
```

## CloudFormation Resources

**infrastructure.yaml creates:**
- **OutputBucket**: S3 bucket with 30-day lifecycle, versioning enabled
- **EcrRepository**: ECR repo with scan-on-push, keeps last 5 images
- **AgentCoreExecutionRole**: IAM role with Bedrock, S3, CloudFront, ECR permissions

**Broad S3 permissions**: Role allows creating `claude-code-*` buckets → Agent can deploy static websites (WebsiteBucketAccess policy lines 107-129)

## Error Handling

**ProcessError (agent.py:206):**
- Raised when Claude Code CLI exits non-zero
- Contains stderr output → Check for permission errors, API failures

**Common failures:**
- Missing `OUTPUT_BUCKET_NAME` env var → S3 upload skipped with warning
- Invalid tool name in `allowed_tools` → Agent rejects invocation
- Bedrock API throttling → Retry with exponential backoff (not implemented)

## Development Notes

**Local testing:**
```bash
# Install dependencies
uv sync

# Run server locally (requires AWS credentials)
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=ap-northeast-1
uv run uvicorn agent:app --host 0.0.0.0 --port 8080

# Test endpoint
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"input":{"prompt":"Create a hello world Python script"}}'
```

**Docker local build:**
```bash
docker build --platform linux/arm64 \
  --build-arg OUTPUT_BUCKET_NAME=test-bucket \
  -t claude-code-agent .

docker run --rm -p 8080:8080 \
  -e AWS_REGION=ap-northeast-1 \
  -v ~/.aws:/home/appuser/.aws:ro \
  claude-code-agent
```

## Anti-patterns

- **Hardcoding bucket names**: Use CloudFormation outputs → Avoids manual coordination
- **Missing region in S3 client**: Creates client without region parameter → Defaults to ap-northeast-1, breaks in other regions (fixed agent.py:68)
- **Synchronous query() calls**: SDK uses async generators → Must use `async for`, not `for`
- **Ignoring ProcessError.stderr**: Contains Claude Code diagnostic output → Essential for debugging
- **Manual runtime updates**: Use deploy.sh Python script → Handles create/update logic correctly

## Regional Model IDs

**Claude Haiku 4.5 Inference Profiles:**
- **ap-northeast-1 (Tokyo)**: `jp.anthropic.claude-haiku-4-5-20251001-v1:0`
- **us-east-1 (Virginia)**: `us.anthropic.claude-haiku-4-5-20251001-v1:0`
- **Global (Cross-Region)**: `global.anthropic.claude-haiku-4-5-20251001-v1:0`

**Marketplace Activation Steps:**
1. Add `AWSMarketplaceFullAccess` to IAM user
2. Update CloudFormation with Marketplace permissions (infrastructure.yaml lines 92-97)
3. Wait 10 minutes for IAM propagation
4. Invoke model once: `aws bedrock-runtime invoke-model --model-id jp.anthropic.claude-haiku-4-5-20251001-v1:0 ...`
5. Deploy AgentCore runtime with updated IAM role

## API Gateway Integration

**Why API Gateway?**
- AgentCore has no direct HTTP endpoint → AWS CLI only
- API Gateway + Lambda bridge enables curl-based access
- Same AgentCore runtime, different invocation method

**Architecture:**
1. curl → API Gateway `/invoke` endpoint (with `x-api-key` header)
2. API Gateway validates API Key → rejects without 403
3. Lambda function (Python 3.12) receives request
4. Lambda → `boto3.client('bedrock-agentcore').invoke_agent_runtime()` call
5. AgentCore runtime executes task (FastAPI + Claude Agent SDK)
6. Response flows back: AgentCore → Lambda → API Gateway → curl

**Deployment:**
```bash
# Prerequisites: AgentCore runtime must exist (run ./deploy.sh first)
./deploy_api.sh  # Updates CloudFormation with API Gateway resources
```

**Request format:**
```bash
curl -X POST <api-endpoint> \
  -H "x-api-key: <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Create a hello world app",
    "permission_mode": "acceptEdits",
    "allowed_tools": "Bash,Read,Write"
  }'
```

**Payload schema:**
```json
{
  "prompt": "Create a hello world app",          // required
  "permission_mode": "acceptEdits",              // optional, default: acceptEdits
  "allowed_tools": "Bash,Read,Write,Replace"     // optional, default: full tool set
}
```

**Response format:**
Same as direct invocation - JSON with result text, session metadata, uploaded file URLs.

**Lambda timeout:**
- Set to 900 seconds (15 minutes) → Handles long-running tasks
- Memory: 512 MB → Sufficient for JSON parsing and boto3 calls

**CORS support:**
- `Access-Control-Allow-Origin: *` enabled
- OPTIONS method configured for preflight requests

**API Key Authentication:**
- **Required header**: `x-api-key: <api-key-value>` must be included in all requests
- **Rate limiting**: 10 requests/second, burst 20, daily quota 1000 requests
- **Key retrieval**: `./get_api_key.sh` fetches key and saves to `.api_key` file
- **Key rotation**: Delete/recreate API Key resource in CloudFormation

**Guardrails:**
- **Runtime ARN required**: Must pass `AgentCoreRuntimeArn` parameter to CloudFormation → Get from `deployment.json`
- **IAM permissions**: Lambda needs `bedrock-agentcore:InvokeAgentRuntime` → Managed by CloudFormation
- **boto3 client**: Use `boto3.client('bedrock-agentcore')`, NOT `bedrock-agent-runtime` → Different service
- **invoke method**: Use `invoke_agent_runtime()` with `agentRuntimeArn` and `payload` parameters
- **Response parsing**: Response contains `StreamingBody` in `response['response']` field → Call `.read()` to get bytes
- **Region auto-detection**: Lambda boto3 auto-detects region → Do NOT set `AWS_REGION` env var (reserved)
- **API Key security**: Never commit `.api_key` file to git → Added to .gitignore
- **Rate limits**: 10 req/sec, burst 20, daily quota 1000 → Adjust Usage Plan for production

## Quick Reference

- **Deploy AgentCore**: `./deploy.sh` (full pipeline)
- **Deploy API Gateway**: `./deploy_api.sh` (optional, for curl access)
- **Get API Key**: `./get_api_key.sh` (retrieve API key for authentication)
- **Invoke (AWS CLI)**: `./invoke_claude_code.sh "task"` (direct AgentCore)
- **Invoke (curl)**: `./test_api.sh "task"` (via API Gateway with API Key)
- **Download**: `./download_outputs.sh` (fetch S3 files)
- **Info**: `./show_agent_info.sh` (view deployment)
- **Logs**: `/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT`
- **Model**: Claude Haiku 4.5 (`jp.anthropic.claude-haiku-4-5-20251001-v1:0`)
- **Region**: ap-northeast-1 (Tokyo)
- **Workspace**: `/app/workspace` (container directory for file operations)
- **AgentCore Endpoint**: `POST /invocations` (internal, not directly accessible)
- **API Gateway Endpoint**: `POST https://<api-id>.execute-api.ap-northeast-1.amazonaws.com/prod/invoke` (requires `x-api-key` header)
- **Rate Limit**: 10 req/sec, burst 20, daily quota 1000
- **Health**: `GET /ping` (returns `{"status": "healthy"}`)
