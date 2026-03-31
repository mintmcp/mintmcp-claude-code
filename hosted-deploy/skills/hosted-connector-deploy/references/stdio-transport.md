# stdio Transport on MintMCP Hosted

stdio is supported but NOT the preferred transport. Use HTTP when possible.

## How it works

MintMCP wraps stdio servers automatically so they can be served over HTTP. The
platform handles all the bridging — the server author just needs to provide a
working stdio MCP server.

## Requirements for stdio images

The Docker image MUST include:
- **Node.js and npx** (required by the platform for stdio mode)
- The MCP server and all its dependencies
- A startup command that runs the server over stdio

Good base images: `node:20-slim`, `nikolaik/python-nodejs:python3.12-nodejs22-slim`

## Dockerfile example (stdio Python server)

```dockerfile
FROM nikolaik/python-nodejs:python3.12-nodejs22-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "server.py"]
EXPOSE 8000
```

Deploy with `--transport stdio` and `--startup-command "python server.py"`.

## Tradeoffs vs HTTP

| Aspect | stdio | HTTP |
|--------|-------|------|
| Startup latency | Higher (new process per session) | Low (single long-lived process) |
| Resource usage | Higher (N processes for N sessions) | Lower (single process) |
| Per-user env | Automatic (no code changes) | Server must handle per-request |
| Stability | Less stable | More stable |

## When to use stdio

- Server only supports stdio and cannot be modified
- Need per-user env without any server code changes
- Prototyping / quick deployment of existing stdio servers
