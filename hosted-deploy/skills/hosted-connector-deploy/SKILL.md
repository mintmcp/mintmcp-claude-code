---
name: hosted-connector-deploy
description: "Deploy MCP servers as hosted connectors on MintMCP using Docker containers. Use when: (1) building a Dockerfile for an MCP server to deploy on MintMCP, (2) testing a container image locally with hosted-cli, (3) deploying or updating a hosted connector via hosted-cli build-and-deploy/deploy, (4) configuring per-user environment variables for hosted connectors, (5) adapting a stdio-only MCP server for hosted deployment. Trigger on: Dockerfile creation for MCP servers, hosted-cli commands, hosted connector deployment, per-user env setup, or questions about MintMCP hosting."
---

# Deploy MCP Servers as Hosted Connectors

Guide users through building, testing, and deploying Docker-based MCP servers on MintMCP.

## Decision Tree

1. **Transport: Use HTTP whenever the server supports it.**
   - If the server has any HTTP streamable support -> use HTTP. Configure it to
     serve at `/mcp` on port 8000. This is the happy path.
   - Only fall back to stdio if the server exclusively supports stdio.
     See [references/stdio-transport.md](references/stdio-transport.md)

2. **How does the server take credentials?** Ask the user which applies:

   **a) No credentials** -> No special handling. Proceed to step 3.

   **b) API key / token** -> Ask how the server receives it (env var, header, etc.),
   then ask: is this a single shared key for the whole org, or does each user
   bring their own?
   - **Shared key** -> Set it as a fixed env var in the Dockerfile or MintMCP
     connector config. No special handling needed.
   - **Per-user keys** -> See [references/per-user-env.md](references/per-user-env.md).
     The server must handle credentials per-request and not require them at startup.

   **c) OAuth** -> See [references/oauth.md](references/oauth.md).

3. **Is there an existing Dockerfile?**
   - Yes -> Review it against the requirements below, then test and deploy
   - No -> Create one following the Dockerfile template

## Requirements

- Image serves MCP over HTTP at `/mcp` on port **8000**
- `initialize` and `tools/list` succeed WITHOUT per-user credential env vars
- Image is self-contained with all dependencies
- Image size: warn >250 MB, reject >1 GB
- Platform: `linux/amd64`
- Fixed env vars baked into the image or set in MintMCP connector config
- Per-user credentials handled per-request, not required at startup

## Dockerfile Template (HTTP, Python/FastMCP)

```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["python", "server.py"]
```

The server should bind to `0.0.0.0:8000` and serve at `/mcp`. Example with FastMCP:

```python
from fastmcp import FastMCP

mcp = FastMCP("my-connector")

@mcp.tool()
async def hello(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8000, path="/mcp")
```

## Dockerfile Template (HTTP, Node/TypeScript)

```dockerfile
FROM node:20-slim AS build
WORKDIR /app
COPY . .
RUN npm ci
RUN npm run build

FROM node:20-slim
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist /app/dist
COPY --from=build /app/package.json /app/package-lock.json ./
RUN npm ci --ignore-scripts --omit=dev && npm cache clean --force
EXPOSE 8000
CMD ["node", "dist/index.js"]
```

Note: `COPY . .` before `npm ci` is intentional — many packages have a `prepare` script
that runs `tsc` during install, which needs the source files present. If the package has
no `prepare` script, you can split `COPY package.json` / `npm ci` / `COPY . .` for
better layer caching.

## Workflow

### Step 1: Create or review Dockerfile

Ensure it meets the requirements above. Key checks:
- Serves at `/mcp` on port 8000
- No credential env vars required at startup
- Multi-stage build if applicable (keeps image small)

### Step 2: Authenticate with hosted-cli

```sh
npx @mintmcp/hosted-cli auth login
```

### Step 3: Test locally

```sh
npx @mintmcp/hosted-cli test-image --dockerfile Dockerfile --context .
```

This builds the image, starts it locally, and verifies the server responds to MCP
requests correctly.

Pass env vars for testing:
```sh
npx @mintmcp/hosted-cli test-image --dockerfile Dockerfile --context . -e API_KEY=test
```

### Step 4: Deploy

**New connector from Dockerfile (build + push + create):**
```sh
npx @mintmcp/hosted-cli build-and-push --name "My Connector" --transport http --dockerfile Dockerfile --context .
```
`build-and-push` builds the image, pushes it, and creates the connector.
Use `--name` and `--transport` for new connectors.

**Update existing connector** (from same directory with `.mintmcp/hosted.json`):
```sh
npx @mintmcp/hosted-cli build-and-push --dockerfile Dockerfile --context .
```

**Deploy from pre-built image (already in a registry):**
```sh
npx @mintmcp/hosted-cli deploy -n "My Connector" --image ghcr.io/org/my-server:latest -t http
```

**Note:** `build-and-deploy` requires `--image` pointing to an existing registry ref.
It does NOT build from a Dockerfile. Use `build-and-push` when building from source.

### Step 5: Configure env vars

After deployment, the CLI prints a connector settings URL. Go there to:
- Set global env vars (same for all users)
- Set per-user env vars (each user prompted for their values)

## Common Issues

**Container exits before probe succeeds:**
- Check the server actually binds to `0.0.0.0:8000` (not `127.0.0.1`)
- Ensure `/mcp` endpoint handles POST with JSON-RPC `initialize` method
- Check for missing env vars required at startup (remove these requirements)

**Image too large:**
- Use multi-stage builds
- Use slim base images (`python:3.12-slim`, `node:20-slim`)
- Remove dev dependencies in final stage

**Per-user env not reaching the server:**
- HTTP header names are case-insensitive; most frameworks normalize to lowercase
- Ensure var names are valid HTTP header tokens (alphanumeric, hyphens, underscores)
