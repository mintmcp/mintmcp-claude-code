---
name: mint-mcp-builder
description: Build a remote MCP server that wraps a third-party REST API and publish it as a linux/amd64 Docker image for the MintMCP hosted runtime. Use this when the user asks to "build an MCP server for X" and mentions MintMCP, or asks to "build and push to mintmcp on Docker Hub", or references hosting an MCP server on mintmcp.com. Covers the full pipeline: TypeScript + streamable HTTP (preferred) or stdio + structured I/O + multi-stage Docker build + correct-architecture push.
---

# Building MCP servers for MintMCP

This skill captures the exact recipe for shipping a new MCP server to the MintMCP hosted runtime. Follow it top-to-bottom; the tricky bits (architecture, port, auth split, stateless server wiring) are called out with **Gotcha** banners.

## 1. Architecture & contract with the runtime

MintMCP is a hosted runtime that runs your container and handles OAuth on the frontend. The division of responsibility:

| Concern | Handled by | How it reaches the server |
| --- | --- | --- |
| OAuth flow, token refresh | MintMCP frontend | — |
| Per-user **access token** | MintMCP → your container | `Authorization: Bearer <token>` header on every request |
| Deployment-scoped IDs (realm/account/tenant ID, environment/region) | Operator at deploy time | Environment variables, read once at startup |
| Transport | **Streamable HTTP (preferred)** or stdio | POST `/mcp` for HTTP; stdin/stdout for stdio |

**Gotcha — split auth correctly.** Only the thing that varies per request (the access token) should come via header. Tenant/realm/account/environment IDs are fixed per deployment and belong in env vars. Don't make the client pass them every call.

## 2. Transport: Streamable HTTP (preferred) vs stdio

MintMCP supports **both** transports. Prefer streamable HTTP.

| Criterion | Streamable HTTP | Stdio |
| --- | --- | --- |
| Recommendation | **Default** | Fallback |
| Runs directly in the container | Yes — MintMCP routes requests straight to your server | No — MintMCP wraps your binary with `@mintmcp/stdio-to-server`, which spawns a child process per session and bridges to HTTP |
| Latency | Low — single process serves all sessions | Higher — cold-start per session, session-timeout cleanup |
| Concurrency | High — one McpServer serves all POSTs | Lower — one child per session |
| Auth forwarding | `Authorization: Bearer` header read directly | Forwarded by the adapter (config-dependent) |
| Good for | Typical REST-wrapping servers | Existing stdio-only MCP servers you don't want to rewrite |

Use stdio only if you already have a working stdio MCP server. For new builds, write streamable HTTP.

## 3. The mandatory constants

These are not configurable. Bake them into the image.

- **Port: `8000`.** MintMCP's runtime probes and routes to port 8000. Not 3000, not 8080. The server must listen there regardless of any `$PORT` env var the platform might inject (platforms sometimes set `PORT=8080`; your server should ignore that and stay on 8000). Hard-code it: `const PORT = 8000;` and `EXPOSE 8000`.
- **Architecture: `linux/amd64`.** MintMCP's hosts are amd64. Building natively on Apple Silicon produces arm64 images that crash-loop with `Exec format error (os error 8)`. Always build with `docker buildx build --platform linux/amd64 --push`.

## 4. Stack

- **Language:** TypeScript (strict mode, NodeNext modules, target ES2022).
- **Runtime:** Node 22 (`node:22-slim` image).
- **SDK:** `@modelcontextprotocol/sdk` (`^1.0.0`).
- **HTTP:** `express` (`^4.21.2`).
- **Schemas:** `zod` (`^3.23.8`).

## 5. Project layout

```
<service>-mcp/
├── package.json
├── tsconfig.json
├── Dockerfile
├── .dockerignore
├── .gitignore
├── README.md
└── src/
    ├── index.ts           # HTTP entry — module-scope server + per-request context
    ├── server.ts          # createServer(ctx) factory
    ├── api-client.ts      # REST client — reads credentials from AsyncLocalStorage
    ├── schemas/
    │   ├── common.ts      # Reference, Address, pagination, query helpers
    │   └── entities.ts    # per-entity create/update/output shapes
    └── tools/
        ├── index.ts       # registerAllTools — wires each entity
        ├── crud-helpers.ts# generic CRUD tool registrar
        └── reports.ts     # any non-CRUD tools (reports, actions)
```

## 6. Tool design rules (non-negotiable)

1. **Every tool declares both `inputSchema` AND `outputSchema`.** No generic "params" blob. Operators and users should be able to read the tool list and know exactly what goes in and what comes out.
2. **Every tool returns `structuredContent` alongside a text block.** Clients that support structured output parse it directly.
3. **Use Zod raw shapes** (`{ field: z.string(), ... }`) — that's what `server.registerTool` expects for `inputSchema`/`outputSchema`. Not `z.object({...})`.
4. **Annotate every tool** with `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`.
5. **Actionable errors.** When updates require a version token (SyncToken/ETag/etc.), say so in the tool description *and* surface the upstream error message verbatim.

### Output-schema tolerance pattern

Real upstream APIs return partial objects, empty sub-objects (`PrimaryPhone: {}`), and undocumented extensions. If your output schema is strict, tools will fail with `Output validation error` even though the call succeeded.

Two rules that keep things working:

- **Nested objects:** `.passthrough()` + every field `.optional()`.
- **Leaf contact schemas (Phone/Email/Web/Reference/Address):** every inner field `.optional()`, `.passthrough()` on the outer.

Example:

```ts
export const PhoneSchema = z
  .object({ FreeFormNumber: z.string().optional() })
  .passthrough();

export const ReferenceSchema = z
  .object({ value: z.string().optional(), name: z.string().optional(), type: z.string().optional() })
  .passthrough();
```

This is the difference between "schema declares a typed shape" (kept) and "schema rejects the reality of the upstream" (bug).

### Input-schema robustness: `z.coerce` for numeric pagination

MintMCP's transport layer occasionally stringifies numeric tool arguments in flight (e.g. `maxResults: 2` arrives as `"2"`). For pagination and other numeric tool inputs, use `z.coerce.number()` so stringified numerics coerce cleanly without hiding real bugs:

```ts
maxResults: z.coerce.number().int().min(1).max(1000).optional(),
startPosition: z.coerce.number().int().min(1).optional(),
```

Don't coerce money/quantity fields — those should fail loudly if a client sends garbage.

## 7. The streamable-HTTP entry (`src/index.ts`)

**Gotcha — don't create a fresh McpServer per request.** Registering dozens of Zod schemas on every POST wastes CPU and can push the first `initialize` past the platform's probe timeout, causing deploy failures that look like health-check flaps. Instead, build the server **once** at module scope and use `AsyncLocalStorage` to scope per-request credentials.

**Gotcha — `enableJsonResponse: true` can break MintMCP.** Omit it. Default streamable-HTTP (SSE-capable) is what the platform's adapters expect.

**Gotcha — bind to `"0.0.0.0"` explicitly.** `app.listen(PORT)` without the host arg binds dual-stack IPv6 in Node, and some hosted platforms' TCP health check probes IPv4 and sees nothing. Always: `app.listen(PORT, "0.0.0.0", cb)`.

```ts
import express, { type Request, type Response } from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { createServer } from "./server.js";
import { requestContext } from "./api-client.js";

const PORT = 8000;  // hard-coded; MintMCP requires 8000
const MCP_PATH = process.env.MCP_PATH ?? "/mcp";

const TENANT_ID = process.env.SERVICE_TENANT_ID;
if (!TENANT_ID) {
  console.error("[service-mcp] SERVICE_TENANT_ID is required.");
  process.exit(1);
}

// Build the McpServer ONCE at startup. Tools registered once here, not per request.
const server = createServer({ tenantId: TENANT_ID });

const app = express();
app.use(express.json({ limit: "10mb" }));

app.get("/healthz", (_req, res) => res.json({ status: "ok" }));
app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.post(MCP_PATH, async (req: Request, res: Response) => {
  const authHeader = req.header("authorization") ?? req.header("Authorization") ?? "";
  const accessToken = authHeader.startsWith("Bearer ")
    ? authHeader.slice("Bearer ".length).trim()
    : "";

  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // stateless
    // NOTE: do NOT set enableJsonResponse — default (SSE-capable) is what MintMCP expects
  });

  requestContext.run({ accessToken }, async () => {
    try {
      res.on("close", () => { transport.close().catch(() => {}); });
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch (err) {
      console.error("[service-mcp] MCP request error:", err);
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: "2.0",
          error: { code: -32603, message: err instanceof Error ? err.message : "Internal error" },
          id: null,
        });
      }
    }
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`[service-mcp] listening on 0.0.0.0:${PORT}${MCP_PATH}`);
});
```

### The per-request context

`src/api-client.ts`:

```ts
import { AsyncLocalStorage } from "node:async_hooks";

export const requestContext = new AsyncLocalStorage<{ accessToken: string }>();

export class ApiClient {
  constructor(private readonly deployment: { tenantId: string }) {}

  private getToken(): string {
    const ctx = requestContext.getStore();
    if (!ctx?.accessToken) {
      throw new Error("Missing access token. Forward it as 'Authorization: Bearer <token>'.");
    }
    return ctx.accessToken;
  }

  async request(...) { /* uses this.getToken() */ }
}
```

Tools call `new ApiClient(deployment).request(...)`; the client pulls the token from AsyncLocalStorage at call time.

## 8. Generic CRUD helper pattern

When wrapping a REST API with many similar entities, don't copy-paste 5 tools × 25 entities. Write **one** helper that takes entity config and registers all CRUD tools:

```ts
export interface CrudToolConfig {
  entity: string;              // upstream entity name, e.g. "Customer"
  toolSuffix: string;          // singular snake_case, e.g. "customer"
  toolSuffixPlural: string;    // plural snake_case, e.g. "customers"
  description: string;
  createShape: ZodRawShape;
  updateShape: ZodRawShape;    // don't include Id/version — added automatically
  entityShape: ZodRawShape;    // output shape
  supportsDelete?: boolean;    // default true
  supportsSparseUpdate?: boolean; // default true
  supportsVoid?: boolean;      // for entities with a void operation
}
```

Per-entity file becomes one call:

```ts
registerCrudTools(server, ctx, {
  entity: "Customer",
  toolSuffix: "customer",
  toolSuffixPlural: "customers",
  description: "customer",
  createShape: CustomerCreateShape,
  updateShape: CustomerUpdateShape,
  entityShape: CustomerOutputShape,
});
```

**Be careful about enabling `supportsDelete`.** Many upstreams silently reject delete on master entities (QB returns `"Operation Delete is not supported"` for Item and Employee; use sparse-update with `Active: false` instead). Audit per entity against the real API.

## 9. Shared helpers to factor out

- `buildQueryString(entity, { where, orderBy, startPosition, maxResults })` — if the upstream uses SQL-like queries.
- `parseQueryResponse(entity, raw)` — strip the upstream envelope down to `{ entities, totalCount, startPosition, maxResults }`.
- `unwrapEntity(entity, raw)` — when the API returns `{ Customer: {...}, time: "..." }`, pull out the inner object so `structuredContent` is tidy.
- `ApiError` — custom error class that preserves HTTP status and raw body; extract human-readable messages from the upstream's error envelope (e.g. `Fault.Error[0].Detail`).

## 10. Dockerfile (node:22-slim, multi-stage, non-root)

```dockerfile
# syntax=docker/dockerfile:1.7

FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 8000
CMD ["node", "dist/index.js"]
```

**Port reminder: the container MUST listen on 8000.** Don't set `ENV PORT=...` — hard-code `8000` in the source so no platform-injected `$PORT` can steer the listener elsewhere.

**Non-root user:** add `USER node`. Many hosting platforms refuse to run as root or degrade security posture when you do.

### `.dockerignore`

```
node_modules
dist
.git
.gitignore
.DS_Store
*.log
.env
.env.*
README.md
```

## 11. Build and push — linux/amd64 is mandatory

Building natively on Apple Silicon produces arm64 images that crash the MintMCP VM with `Exec format error (os error 8)` and a reboot loop. Always use buildx with `--platform linux/amd64`.

```bash
# One-time: create a docker-container driver builder (needed for cross-arch)
docker buildx create --name mintmcp-builder --driver docker-container --use

# Every release:
docker buildx build \
  --builder mintmcp-builder \
  --platform linux/amd64 \
  -t mintmcp/<service>-mcp:latest \
  -t mintmcp/<service>-mcp:<version> \
  --push \
  .
```

Image naming: `mintmcp/<service>-mcp` on Docker Hub. Push both `:latest` and a version tag matching `package.json`.

## 12. Local smoke test before pushing

Run the exact image (pulling amd64 on an arm64 Mac works via Docker Desktop's QEMU):

```bash
docker run --rm -p 8000:8000 -e SERVICE_TENANT_ID=<id> mintmcp/<service>-mcp:latest
```

Then hit it:

```bash
curl -s http://localhost:8000/healthz

curl -s -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer fake-token" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'

curl -s -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer fake-token" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}' \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const raw=d.split('\n').find(l=>l.startsWith('data: '))?.slice(6)??d;console.log('tools:',JSON.parse(raw).result?.tools?.length)})"
```

Minimum bar before pushing: healthz 200, missing-auth 401 with clear message, `initialize` returns protocolVersion, `tools/list` returns expected tool count, and a spot-checked tool has both `inputSchema.required` populated and a non-empty `outputSchema.properties`.

## 13. README checklist

- Per-request auth (the `Authorization: Bearer` header — **only** that).
- A table of env vars with Required/Default columns.
- `docker run` example with env vars filled in.
- `curl` example hitting `tools/call`.
- List of tool categories (not every tool — the groupings).

## 14. Decision cheat sheet

| Question | Answer |
| --- | --- |
| Where does the access token live? | `Authorization: Bearer …` header, per request. |
| Where do tenant/realm/account/environment IDs live? | Env var, read at startup, required (exit 1 if missing). |
| Module-scope or per-request `McpServer`? | **Module-scope**, tools registered once at boot. Use AsyncLocalStorage for per-request token. |
| `enableJsonResponse: true`? | No — omit it. Default (SSE-capable) works with MintMCP. |
| Listen host? | `"0.0.0.0"` explicitly. |
| Port? | 8000, hard-coded. Not 3000, not 8080. |
| Should a tool take a generic `params` object? | No. Structured Zod shape per tool. |
| Full-entity schema or passthrough? | Both — named fields for common/important ones, `.passthrough()` for the tail, nested fields optional. |
| Pagination field types? | `z.coerce.number().int()` — bridge sometimes stringifies. |
| Image base? | `node:22-slim`, multi-stage, non-root (`USER node`). |
| Image architecture? | `linux/amd64`. Always. |
| Docker Hub namespace? | `mintmcp/<service>-mcp`. |
| Tags to push? | `:latest` and `:<semver>`. |

## 15. Common failure signatures and their fix

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Exec format error (os error 8)` + VM reboot loop | arm64 image pushed, amd64 runtime | Rebuild with `--platform linux/amd64` via buildx and `--push`. |
| Fly `servicecheck-00-tcp-8000` keeps failing; server says it's listening | `app.listen(PORT)` only bound IPv6 | Add `"0.0.0.0"`: `app.listen(PORT, "0.0.0.0", cb)`. |
| First probe races the boot, then health check passes | Cold-start registering Zod schemas per request | Move `createServer` call to module scope. |
| Hosted runtime logs show port 8080 even though you set 8000 | Platform injected `PORT=8080`; code read `process.env.PORT` | Hard-code `const PORT = 8000;` — don't read from env. |
| MintMCP's stdio-to-server wrapper gets invoked as a fallback | Your streamable HTTP server isn't passing the platform's readiness probe | Fix the HTTP server (likely IPv4 bind or per-request perf), don't switch transports. |
| 401 on every call from MintMCP | Expecting non-Authorization headers | Drop custom headers; read tenant from env. |
| Second concurrent request sees the first request's token | Credentials stored on a singleton rather than scoped per request | Use `AsyncLocalStorage.run(...)` around `transport.handleRequest`. |
| `Output validation error: entity.PrimaryPhone.FreeFormNumber … Required` | Output schema too strict for empty sub-objects | Make inner fields `.optional()`; add `.passthrough()` on the nested schema. |
| `Input validation error: Expected number, received string` | MintMCP bridge stringified a numeric arg | Use `z.coerce.number().int()` on pagination inputs (not on money/quantity). |
| `tools/list` shows `inputSchema` missing fields | Passed `z.object({...})` instead of the raw shape | Pass the shape object (`{ x: z.string() }`), not `z.object({ x: z.string() })`. |
| TypeScript error "Conversion of type … may be a mistake" when casting input | Over-narrow target type | Use `as Parameters<typeof helper>[N]` instead of `as Record<string, never>`. |
| Upstream returns `"Operation Delete is not supported"` on a master entity | Some APIs don't support hard delete (QB Item/Employee) | Set `supportsDelete: false`; use sparse-update with `Active: false`. |
| Write succeeds but a later update fails with `Stale Object Error` / stale ETag | Side-effect bumped the entity's version token | Re-read the entity (`get_<entity>`) before the update. |

## 16. When the user asks to build a new MintMCP server

Default workflow:

1. Fetch the upstream API's reference tool list (e.g. `github.com/<org>/<service>-mcp-server`) and the API docs.
2. Scaffold per section 5. Hard-code port 8000, bind `"0.0.0.0"`, module-scope server, split-auth model — all from day one.
3. Factor out a generic CRUD helper before writing the first entity; REST APIs almost always repeat the same 5-tool shape.
4. Model common fields explicitly with Zod; `.passthrough()` + inner-optional for the tail. Use `z.coerce.number()` for numeric inputs.
5. `npm run build` → boot locally → curl `tools/list` and verify tool count.
6. Smoke-test reads against a sandbox before shipping.
7. `docker buildx build --platform linux/amd64 --push` with `mintmcp/<service>-mcp:{latest,<version>}`.
8. Write a focused README (section 13).

Confirm destructive actions (pushing to Docker Hub, deleting tags, write-path tests against non-sandbox data) before running them unless the user has explicitly pre-authorized that run.
