import json
import logging
import random
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    request_id = context.aws_request_id if context else "local-test"
    simulated_service = "payment-service"

    error_scenarios = [
        {
            "error_type": "DatabaseConnectionError",
            "message": "Failed to connect to the orders database after 3 retries.",
            "severity": "HIGH",
            "possible_cause": "Database endpoint unreachable or security group misconfiguration"
        },
        {
            "error_type": "TimeoutError",
            "message": "Request timed out while calling downstream inventory service.",
            "severity": "MEDIUM",
            "possible_cause": "Downstream service latency or network timeout"
        },
        {
            "error_type": "AccessDeniedError",
            "message": "Application does not have permission to read required S3 object.",
            "severity": "HIGH",
            "possible_cause": "Missing IAM permission or incorrect bucket policy"
        },
        {
            "error_type": "ThrottlingException",
            "message": "Too many requests sent to external payment API.",
            "severity": "MEDIUM",
            "possible_cause": "API rate limit exceeded"
        }
    ]

    scenario = random.choice(error_scenarios)

    log_payload = {
        "timestamp": int(time.time()),
        "request_id": request_id,
        "service": simulated_service,
        "status": "ERROR",
        "error_type": scenario["error_type"],
        "message": scenario["message"],
        "severity": scenario["severity"],
        "possible_cause": scenario["possible_cause"]
    }

    logger.error(json.dumps(log_payload))

    return {
        "statusCode": 500,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({
            "message": "Simulated application error generated",
            "request_id": request_id,
            "service": simulated_service,
            "error_type": scenario["error_type"],
            "severity": scenario["severity"]
        })
    }