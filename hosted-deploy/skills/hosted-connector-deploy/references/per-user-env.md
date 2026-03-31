# Per-User Environment Variables

MintMCP supports per-user env vars so each user connecting to a shared hosted connector
can supply their own credentials (API keys, tokens, etc.).

## How it works by transport

### HTTP transport (preferred)

Per-user env values are delivered to the server as HTTP headers on every request.
The server implementation should ideally handle credentials on a per-request basis
rather than relying on process-level env vars.

### stdio transport

MintMCP handles per-user env vars automatically for stdio servers — no code
changes needed. The server just reads `process.env.API_KEY` as normal.

The tradeoff: stdio mode is slower and more resource-heavy than HTTP.

## Startup vs request-time credentials

**Critical design rule:** Servers should NOT require credential env vars at startup.

MintMCP often starts the container before any user has connected. The `initialize`
and `tools/list` MCP calls happen during health probes and connector setup, before any
user credentials are available.

**Pattern to follow:**
- Global config (non-secret): set as fixed env vars in the Dockerfile or MintMCP config
- Per-user credentials: read just-in-time on actual data/tool calls, not on startup
- `initialize` and `tools/list` must succeed without per-user credentials

**Bad:**
```python
# Crashes on startup if API_KEY not set
api_key = os.environ["API_KEY"]  # Required at module load
```

**Good:**
```python
@mcp.tool()
async def fetch_data(ctx, query: str) -> str:
    api_key = os.environ.get("API_KEY")
    if not api_key:
        return "Error: API_KEY not configured. Set it in your MintMCP connection settings."
    # Use api_key only when needed
```

## Configuring per-user env vars in MintMCP

After deploying, go to the connector settings URL and click "Edit" in the
"Server Configuration" section. Under "Environment Variables":

- **Global**: Fixed value, same for all users (e.g., `LOG_LEVEL=info`)
- **Per-User**: Each user is prompted for their value on first connection
