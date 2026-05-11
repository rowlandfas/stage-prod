#!/bin/bash

# Set variables
TERRAFORM_CODE_DIR="./"
CHECKOV_OUTPUT_FILE="checkov_output.json"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

# Run Checkov scan
checkov -d "$TERRAFORM_CODE_DIR" -o cli > "$CHECKOV_OUTPUT_FILE"

# Check if Checkov ran successfully
if [ $? -ne 0 ]; then
  echo "Checkov scan failed."
  exit 0
fi

# Debug: Print Checkov output file content
echo "====== Checkov Output ======"
cat "$CHECKOV_OUTPUT_FILE"
echo "============================"

# Parse Checkov output
critical_issues=$(jq '.results.failed_checks | map(select(.severity == "CRITICAL")) | length' "$CHECKOV_OUTPUT_FILE")
high_issues=$(jq '.results.failed_checks | map(select(.severity == "HIGH")) | length' "$CHECKOV_OUTPUT_FILE")

# Debug: Print parsed values
echo "Critical issues: $critical_issues"
echo "High issues: $high_issues"

# Check if vulnerabilities exist
if [ "$critical_issues" -gt 0 ] || [ "$high_issues" -gt 0 ]; then
  message="Checkov Scan Alert! Critical: $critical_issues, High: $high_issues"
  echo "Sending message to Slack: $message"

  # Send alert to Slack
  curl --ssl-no-revoke -X POST --data-urlencode \
    "payload={\"channel\": \"#24th-february-jenkins-pipeline-project-team-1\", \"username\": \"ACP-TEAM\", \"text\": \"$message\", \"icon_emoji\": \":ghost:\"}" \
    "$SLACK_WEBHOOK_URL"

else
  summary="No critical or high vulnerabilities found in Checkov scan."
  echo "Sending summary to Slack: $summary"

  curl --ssl-no-revoke -X POST --data-urlencode \
    "payload={\"channel\": \"#24th-february-jenkins-pipeline-project-team-1\", \"username\": \"ACP-TEAM\", \"text\": \"$summary\", \"icon_emoji\": \":white_check_mark:\"}" \
    "$SLACK_WEBHOOK_URL"
fi
