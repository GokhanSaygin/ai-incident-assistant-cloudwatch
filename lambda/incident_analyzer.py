import json
import os
import time
import uuid
import boto3

logs_client = boto3.client("logs")
bedrock_client = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")

ERROR_LOG_GROUP = os.environ["ERROR_LOG_GROUP"]
INCIDENT_TABLE = os.environ["INCIDENT_TABLE"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-micro-v1:0")


def extract_json_from_log(message):
    """
    CloudWatch log message sometimes includes Lambda metadata before the JSON.
    This function extracts the JSON object from the log message.
    """
    try:
        start = message.find("{")
        end = message.rfind("}") + 1

        if start == -1 or end == 0:
            return None

        return json.loads(message[start:end])
    except Exception:
        return None


def get_recent_error_logs(minutes=15):
    """
    Reads recent ERROR logs from the error generator Lambda log group.
    """
    end_time = int(time.time() * 1000)
    start_time = end_time - (minutes * 60 * 1000)

    response = logs_client.filter_log_events(
        logGroupName=ERROR_LOG_GROUP,
        startTime=start_time,
        endTime=end_time,
        filterPattern="ERROR",
        limit=10
    )

    error_events = []

    for event in response.get("events", []):
        parsed_log = extract_json_from_log(event.get("message", ""))

        if parsed_log and parsed_log.get("status") == "ERROR":
            error_events.append(parsed_log)

    return error_events


def generate_incident_summary(error_events):
    """
    Sends recent error logs to Amazon Bedrock and asks for an incident summary.
    """
    if not error_events:
        return "No recent error logs found."

    prompt = f"""
You are an AI incident response assistant for a Cloud Engineer.

Analyze the following CloudWatch application error logs and generate a concise incident report.

Return the answer with these sections:
1. Incident Summary
2. Affected Service
3. Severity
4. Possible Root Cause
5. Recommended Troubleshooting Steps
6. AWS Services to Check

CloudWatch error logs:
{json.dumps(error_events, indent=2)}
"""

    response = bedrock_client.converse(
        modelId=BEDROCK_MODEL_ID,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "text": prompt
                    }
                ]
            }
        ],
        inferenceConfig={
            "maxTokens": 700,
            "temperature": 0.2
        }
    )

    return response["output"]["message"]["content"][0]["text"]


def lambda_handler(event, context):
    error_events = get_recent_error_logs(minutes=15)

    incident_summary = generate_incident_summary(error_events)

    incident_id = str(uuid.uuid4())

    table = dynamodb.Table(INCIDENT_TABLE)

    item = {
        "incident_id": incident_id,
        "created_at": int(time.time()),
        "log_group": ERROR_LOG_GROUP,
        "error_count": len(error_events),
        "summary": incident_summary,
        "raw_errors": error_events
    }

    table.put_item(Item=item)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({
            "incident_id": incident_id,
            "error_count": len(error_events),
            "summary": incident_summary
        })
    }