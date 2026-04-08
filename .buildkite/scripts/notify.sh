#!/usr/bin/env bash
# ─── Post-Deploy Notification ────────────────────────────────────────────────
# Sends a Slack notification after a successful deploy to all regions.
# Includes links to the build, Datadog dashboard, and rollback instructions.

set -euo pipefail

SLACK_CHANNEL="${SLACK_CHANNEL:-#platform-deploys}"
SERVICE="${SERVICE:-product-catalog}"
VERSION="${VERSION:-unknown}"
BUILD_URL="${BUILD_URL:-${BUILDKITE_BUILD_URL:-unknown}}"
SHORT_SHA="${VERSION:0:8}"

echo "--- :mega: Sending deploy notification to ${SLACK_CHANNEL}"

# Build Slack message payload
PAYLOAD=$(cat <<EOF
{
  "channel": "${SLACK_CHANNEL}",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": ":rocket: ${SERVICE} deployed to production"
      }
    },
    {
      "type": "section",
      "fields": [
        { "type": "mrkdwn", "text": "*Version:*\n\`${SHORT_SHA}\`" },
        { "type": "mrkdwn", "text": "*Regions:*\nus-east-1, ap-southeast-2" },
        { "type": "mrkdwn", "text": "*Pipeline:*\n<${BUILD_URL}|View Build>" },
        { "type": "mrkdwn", "text": "*SLO Dashboard:*\n<https://app.datadoghq.com/slo?query=service:${SERVICE}|View SLOs>" }
      ]
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": ":rewind: Rollback: \`helm rollback ${SERVICE} --namespace production\`"
        }
      ]
    }
  ]
}
EOF
)

# Send to Slack webhook
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  curl -sf -X POST "${SLACK_WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}"
  echo "Notification sent"
else
  echo "SLACK_WEBHOOK_URL not set — skipping notification"
  echo "Would have sent:"
  echo "${PAYLOAD}" | python3 -m json.tool
fi
