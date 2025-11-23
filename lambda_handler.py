"""
Lambda handler for API Gateway -> AgentCore integration.
Receives HTTP POST requests and invokes AgentCore runtime.
"""

import json
import os
import base64
import boto3
from typing import Dict, Any

# Initialize Bedrock AgentCore client
client = boto3.client('bedrock-agent-runtime', region_name=os.environ['AWS_REGION'])


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    API Gateway Lambda proxy integration handler.

    Expected request body:
    {
        "prompt": "Create a hello world app",
        "permission_mode": "acceptEdits",  # optional
        "allowed_tools": "Bash,Read,Write"  # optional
    }
    """
    try:
        # Parse request body
        if 'body' in event:
            if event.get('isBase64Encoded', False):
                body = json.loads(base64.b64decode(event['body']))
            else:
                body = json.loads(event['body'])
        else:
            # Direct invocation (not via API Gateway)
            body = event

        # Extract parameters
        prompt = body.get('prompt')
        if not prompt:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: prompt'})
            }

        permission_mode = body.get('permission_mode', 'acceptEdits')
        allowed_tools = body.get('allowed_tools', 'Bash,Read,Write,Replace,Search,List,WebFetch,AskFollowup')

        # Build AgentCore payload
        agentcore_payload = {
            'input': {
                'prompt': prompt,
                'permission_mode': permission_mode,
                'allowed_tools': allowed_tools
            }
        }

        # Invoke AgentCore runtime
        runtime_arn = os.environ['AGENTCORE_RUNTIME_ARN']

        response = client.invoke_agent(
            agentRuntimeArn=runtime_arn,
            inputText=json.dumps(agentcore_payload)
        )

        # Parse response stream
        result = {}
        if 'completion' in response:
            # Read streaming response
            for event in response['completion']:
                if 'chunk' in event:
                    chunk_data = event['chunk'].get('bytes', b'')
                    if chunk_data:
                        result = json.loads(chunk_data.decode('utf-8'))

        # Return success response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'  # CORS support
            },
            'body': json.dumps(result, ensure_ascii=False)
        }

    except Exception as e:
        print(f"Error invoking AgentCore: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
