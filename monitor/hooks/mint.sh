#!/bin/sh

# If $MINTMCP_URL is not set, return a structured JSON output with exit 0
if [ -z "$MINTMCP_URL" ]; then
    echo '{
  "continue": true,
  "stopReason": "MINTMCP_URL is not set. See https://app.mintmcp.com/llm for details or ask your admin.",
  "suppressOutput": true,
  "systemMessage": "MINTMCP_URL is not set. See https://app.mintmcp.com/llm for details or ask your admin."
}'
    exit 0
fi

# Read JSON input from stdin
json_input=$(cat)

# Post the JSON input to the URL
curl -X POST -H "Content-Type: application/json" -d "$json_input" "$MINTMCP_URL"

exit 0

