"""Reformat a CloudWatch alarm SNS notification into a short, readable email.

Trigger:  SNS topic  <project>-alerts        (raw CloudWatch alarm JSON)
Output:   SNS topic  <project>-alerts-email  (tidy text -> email subscription)
"""

import json
import os
import re
from datetime import datetime, timezone

import boto3

sns = boto3.client("sns")
TARGET_TOPIC_ARN = os.environ["TARGET_TOPIC_ARN"]

ACTION_HINTS = {
    "AWS/EC2": "Check the EC2 instances and Auto Scaling activity.",
    "AWS/ApplicationELB": "Check load balancer target health and recent deploys.",
    "AWS/RDS": "Check database CPU, connections, and slow queries.",
}


def _region_from_arn(arn: str) -> str:
    # arn:aws:cloudwatch:eu-north-1:123456789012:alarm/name
    parts = arn.split(":")
    return parts[3] if len(parts) > 3 else "unknown"


def _format_time(raw: str) -> str:
    # "2026-09-02T10:32:00.123+0000" -> "02 Sep 2026, 10:32 UTC"
    try:
        cleaned = re.sub(r"\.\d+", "", raw).replace("+0000", "+00:00")
        dt = datetime.fromisoformat(cleaned).astimezone(timezone.utc)
        return dt.strftime("%d %b %Y, %H:%M UTC")
    except Exception:
        return raw or "unknown"


def _emoji(state: str) -> str:
    return {
        "ALARM": "\U0001F6A8",           # rotating light
        "OK": "✅",                   # check mark
        "INSUFFICIENT_DATA": "❓",    # question mark
    }.get(state, "\U0001F514")            # bell


def lambda_handler(event, _context):
    for record in event["Records"]:
        alarm = json.loads(record["Sns"]["Message"])

        state = alarm.get("NewStateValue", "UNKNOWN")
        name = alarm.get("AlarmName", "unknown-alarm")
        reason = alarm.get("NewStateReason", "No reason provided.")
        namespace = alarm.get("Trigger", {}).get("Namespace", "")
        hint = ACTION_HINTS.get(namespace, "Open the CloudWatch console and review the metric.")

        # SNS subject: ASCII only, <= 100 chars, no newlines. Emoji goes in the body.
        subject = f"{state}: {name}"[:100]

        body = (
            f"{_emoji(state)} AWS CloudWatch Alarm\n\n"
            f"Alarm:  {name}\n"
            f"Status: {state}\n"
            f"Region: {_region_from_arn(alarm.get('AlarmArn', ''))}\n"
            f"Reason: {reason}\n\n"
            f"Time:   {_format_time(alarm.get('StateChangeTime', ''))}\n\n"
            f"Action: {hint}\n"
        )
        if state == "OK":
            body += "\nRecovery notice - the alarm is back to normal.\n"

        sns.publish(TopicArn=TARGET_TOPIC_ARN, Subject=subject, Message=body)
