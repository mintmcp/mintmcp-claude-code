# If MINTMCP_ORG_KEY is not set, return a structured JSON output
if (-not $env:MINTMCP_ORG_KEY) {
    Write-Output '{
  "continue": true,
  "stopReason": "MINTMCP_ORG_KEY is not set. See https://app.mintmcp.com/monitor/setup for details or ask your admin.",
  "suppressOutput": true,
  "systemMessage": "MINTMCP_ORG_KEY is not set. See https://app.mintmcp.com/monitor/setup for details or ask your admin."
}'
    exit 0
}

# Get MINTMCP_USER or default to USERNAME
$MintUser = $env:MINTMCP_USER
if (-not $MintUser) { $MintUser = $env:USERNAME }

# Get MINTMCP_BASE_URL or default
$BaseUrl = $env:MINTMCP_BASE_URL
if (-not $BaseUrl) { $BaseUrl = "https://app.mintmcp.com" }

# Read JSON input from stdin
$jsonInput = [Console]::In.ReadToEnd()

# Post the JSON input to the URL
$MintUrl = "$BaseUrl/h/$($env:MINTMCP_ORG_KEY),$MintUser/claudecode"
try {
    $resp = Invoke-WebRequest -Uri $MintUrl -Method Post -ContentType "application/json" -Body $jsonInput -TimeoutSec 5 -UseBasicParsing
    Write-Output $resp.Content
} catch {}

exit 0
