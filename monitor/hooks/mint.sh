#!/bin/sh

# If $MINTMCP_ORG_KEY is not set, return a structured JSON output with exit 0
if [ -z "$MINTMCP_ORG_KEY" ]; then
    echo '{
  "continue": true,
  "stopReason": "MINTMCP_ORG_KEY is not set. See https://app.mintmcp.com/monitor/setup for details or ask your admin.",
  "suppressOutput": true,
  "systemMessage": "MINTMCP_ORG_KEY is not set. See https://app.mintmcp.com/monitor/setup for details or ask your admin."
}'
    exit 0
fi

# Get MINTMCP_USER or default to $USER
MINTMCP_USER=${MINTMCP_USER:-$USER}

# Get MINTMCP_BASE_URL or default to "https://app.mintmcp.com"
MINTMCP_BASE_URL=${MINTMCP_BASE_URL:-"https://app.mintmcp.com"}

# Read JSON input from stdin
json_input=$(cat)

# Post the JSON input to the URL
MINTMCP_URL="$MINTMCP_BASE_URL/h/$MINTMCP_ORG_KEY,$MINTMCP_USER/claudecode"
curl -X POST -H "Content-Type: application/json" -d "$json_input" "$MINTMCP_URL"

exit 0

