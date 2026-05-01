---
name: mint-middleware-builder
description: Co-build and deploy a custom MintMCP gateway middleware. Use when the user asks to "build/deploy a middleware", "filter/restrict/mask a tool", "block calls based on arguments/result", or otherwise add a guard rule on a Mint gateway. Walks the user through discovering the right tool inputs, drafting the middleware in QuickJS, testing it via test_gateway_middleware, and saving it via create_gateway_middleware.
---

# Mint middleware builder

Co-build a custom gateway middleware for any Mint-managed MCP. The skill is gateway-agnostic — the SharePoint drive allowlist is the worked example, but the same flow works for filtering Slack channels, blocking destructive Linear actions, masking PII in tool results, etc.

## Required MCPs — ask the user to connect these BEFORE doing anything else

**This is step zero. Do not call any tools, do not search via ToolSearch, do not try to introspect the environment. Just ask.**

The skill needs two MCP servers connected in the user's client (Claude Desktop, Claude Code, claude.ai, etc.):

1. **MintMCP Admin MCP** — to list gateways and create/test/update middleware.
2. **The target MCP server** (e.g. Slack, SharePoint, Linear, GitHub — whatever the rule is *about*) — to introspect tool schemas and discover values (channel IDs, drive IDs, project IDs) the user wants to allowlist/block/mask.

Open your reply with a short message that:
- Names both MCPs needed for *their specific* request (e.g. "MintMCP Admin + Slack").
- Tells them to connect any missing ones at **https://app.mintmcp.com** (the gateways page), then reload their MCP client so the tools surface in this session.
- Asks them to confirm once both are connected before continuing.

Do **not** assume tools are available because the connector logos are visible in some other surface. ToolSearch / `select:` lookups won't conjure tools that aren't actually wired into this client session — searching is not a substitute for asking. Many filtering rules also need values that only the target MCP can produce live (the SharePoint drive_id problem: invisible in the source UI, only fetchable via the MCP), so a missing target MCP isn't just a tooling gap, it breaks step 2 of the flow.

Only after the user confirms connection should you proceed to step 1 below.

## The middleware primitives

Middleware code is JavaScript executed in a sandboxed QuickJS runtime. Limits: 8 MB memory, 5s timeout, max 5 fetch calls.

**Context (`ctx`)**
- `ctx.toolName` `string` — tool being called
- `ctx.arguments` `Record<string, unknown>` — tool call arguments
- `ctx.result` `CallToolResult` — full MCP tool result (post-phase only)
- `ctx.phase` `"pre" | "post"` — current execution phase
- `ctx.secrets` `Record<string, string>` — decrypted secret values

**Built-in functions**
- `fetch(url, opts)` → `{ status, json(), text() }` — HTTP client (allowed domains only)
- `console.log(...)` — captured in test results and logs
- `new OpenAI({ apiKey })` — `.moderations.create()`, `.chat.completions.create()`
- `awsSign({ method, url, body, region, service, accessKeyId, secretAccessKey })` — returns SigV4-signed headers
- `signJwt({ payload, privateKeyPem })` — returns RS256-signed JWT

**Return values**
- `{ action: "allow" }` — let the call through
- `{ action: "block", reason }` — reject with a reason
- `{ action: "mask", maskedArguments }` — replace arguments (pre)
- `{ action: "mask", maskedResult }` — replace tool result (post)
- `{ action: "mask", maskedContent: "..." }` — simple text masking (post)

## Workflow

Co-build, don't dump. Pause at each step so the user can correct course.

### 1. Establish target and intent

Ask:
1. **Which gateway?** Use `admin__list_gateways` to show options. Capture the `gatewayId`.
2. **What rule?** Allow/block/mask, on what condition (specific arg value, presence of a field, regex on result text, classification by an LLM).
3. **Phase?** `pre` for argument-based decisions; `post` for result-based; `both` if you need to mask args *and* sanitize the response.
4. **onError fail-open or fail-closed?** Default `block` for security-critical rules; `allow` for nice-to-have UX guards. If unsure, ask.

### 2. Discover values via the target MCP

This is the step that's easy to skip and easy to get wrong. Most filtering rules key off opaque IDs (drive_id, channel_id, project_id) that the user can't see in the source UI. **Use the target MCP to fetch them, then ask the user to pick.**

Example for SharePoint drive allowlist:
- The SharePoint UI doesn't expose `drive_id`.
- Call `sharepoint__list_drives` and surface a curated subset via `AskUserQuestion` (multiSelect).
- If the list is large (>4), include the most likely candidates plus an "Other" path so the user can paste IDs verbatim.

Do not ask the user to type IDs from memory or guess. Always fetch and present.

### 3. Inspect tool schemas

Call `admin__list_mcp_tools(gatewayId)` to see exactly which tools exist on this gateway, with their argument schemas. Use this to:
- Build the `GUARDED_TOOLS` set (the tools your rule applies to).
- Identify any **discovery tools** that must remain unguarded so the user can still find values to add to the allowlist (e.g. `list_drives`, `list_sites_and_groups`, `search_items`).
- Confirm the argument name you're keying on actually exists on every guarded tool.

### 4. Draft the middleware

Start from a template if one fits the pattern (see "Templates" below). Otherwise build from scratch using the primitives.

Style guide for the code itself:
- Top-of-file comment explaining what the rule does and how to extend it.
- Capitalize allowlist/blocklist constants (`ALLOWED_DRIVE_IDS`).
- Always return `{ action: "allow" }` at the end as the default — guards short-circuit with `block`/`mask`.
- Validate that the keyed-on argument exists; treat missing as block (fail-closed).
- Empty allowlist should block with a clear "add IDs to the allowlist" reason, not silently allow.
- Keep tool name strings exactly as `admin__list_mcp_tools` reports them — most gateways prefix with the connector name (e.g. `sharepoint__list_drive_items`).

### 5. Test before saving

Always run `admin__test_gateway_middleware` with **at least three cases**:
1. **Allow path** — a guarded tool with a valid argument value → expect `allow`.
2. **Block path** — a guarded tool with an invalid value → expect `block` with the right reason.
3. **Discovery passthrough** — an unguarded tool → expect `allow`.

For post-phase masking middleware, also include a `result` payload in the test call. For both-phase middleware, use `phase: "both"` so pre-phase masks are visible to the post phase.

### 6. Save, attach, enable

Once tests pass, call `admin__create_gateway_middleware`. Required fields: `name`, `description`, `code`, `phase`, `onError`. Optional: `allowedDomains` (only if `fetch` is used).

**Important: this modifies shared infrastructure.** Always confirm with the user before calling create_gateway_middleware, even if they previously said "save it to mint" — Mint's permission layer will block unconfirmed shared-infra writes, and the user has a chance to review the final code one more time before it goes live.

After creation, the middleware is registered but **not yet active**. The user must take **two** UI steps at the returned `editUrl`:
1. **Attach** it to the target gateway.
2. **Enable enforcement** (separate toggle). Attaching alone does not enforce — this is intentional, so a freshly attached or freshly updated rule can be reviewed before it starts blocking traffic.

Surface the editUrl and call out both steps. If the user reports the rule "isn't working," the first thing to check is whether enforcement is on.

To add **secrets** (API keys for `fetch`, OpenAI keys, AWS creds), the user must use the secrets editor at the same `editUrl` — secrets cannot be set via the MCP tool.

### 7. Iterate

If the user wants to refine: `admin__update_gateway_middleware` with the `middlewareId` and any changed fields. Re-test before each save.

**Every update requires re-attach + re-enable on the gateway.** This is a canary-style guardrail — a bad rule can't auto-deploy and silently brick traffic. After updating, tell the user to re-attach the new version on the gateway page before retesting against live calls.

## Templates

When starting a new middleware, check whether one of these patterns fits before building from scratch.

### Argument allowlist (pre-phase, block)

Restrict a set of tools to specific values of one argument. Discovery tools stay unguarded.

```javascript
const ALLOWED_VALUES = [
  // "value-1",
];

const GUARDED_TOOLS = new Set([
  // "connector__tool_a",
  // "connector__tool_b",
]);

const KEYED_ARG = "drive_id"; // the argument name to check

if (GUARDED_TOOLS.has(ctx.toolName)) {
  if (ALLOWED_VALUES.length === 0) {
    return { action: "block", reason: "ALLOWED_VALUES is empty — add IDs to the allowlist" };
  }
  const value = ctx.arguments?.[KEYED_ARG];
  if (value == undefined) {
    return { action: "block", reason: "Missing " + KEYED_ARG + " argument" };
  }
  if (!ALLOWED_VALUES.includes(value)) {
    return { action: "block", reason: KEYED_ARG + " " + value + " is not in the allowlist" };
  }
}

return { action: "allow" };
```

### Argument blocklist (pre-phase, block)

Inverse of allowlist — block specific known-bad values.

```javascript
const BLOCKED_VALUES = new Set([
  // "value-to-block",
]);

if (BLOCKED_VALUES.has(ctx.arguments?.channel_id)) {
  return { action: "block", reason: "channel is restricted" };
}

return { action: "allow" };
```

### Argument masking (pre-phase, mask)

Rewrite arguments before they hit the tool — e.g. force `dry_run: true`, scope a query to a tenant.

```javascript
if (ctx.toolName === "connector__send_email") {
  return {
    action: "mask",
    maskedArguments: { ...ctx.arguments, dry_run: true },
  };
}
return { action: "allow" };
```

### Result redaction (post-phase, mask)

Strip or replace content in the tool's response.

```javascript
if (ctx.phase !== "post") return { action: "allow" };

const text = ctx.result?.content?.[0]?.text ?? "";
const redacted = text.replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[REDACTED-SSN]");

if (redacted === text) return { action: "allow" };

return {
  action: "mask",
  maskedResult: {
    ...ctx.result,
    content: [{ type: "text", text: redacted }],
  },
};
```

### LLM-classified block (pre-phase, block)

Use OpenAI to classify the request before allowing.

```javascript
const openai = new OpenAI({ apiKey: ctx.secrets.OPENAI_API_KEY });
const mod = await openai.moderations.create({
  input: JSON.stringify(ctx.arguments),
});
if (mod.results[0]?.flagged) {
  return { action: "block", reason: "flagged by content moderation" };
}
return { action: "allow" };
```

(Requires the OpenAI key be added via the secrets editor at `editUrl`.)

## Worked example: SharePoint drive allowlist

The full flow, end-to-end:

1. **Gateway:** SharePoint (`g_2pC7WK5SYDVC6BJxp0CH5Y`).
2. **Intent:** restrict access to a specific set of SharePoint drives.
3. **Discovery problem:** `drive_id` is not visible in the SharePoint UI. Solve by calling `sharepoint__list_drives` via the target MCP, then asking the user via `AskUserQuestion` (multiSelect) to pick from the actual drives. Surface the most likely candidates as labeled options; rely on "Other" for the long tail.
4. **Tool inspection:** `admin__list_mcp_tools` shows tools prefixed `sharepoint__`. Strip the prefix when writing `GUARDED_TOOLS` — the runtime passes un-prefixed names. Five take `drive_id` (`list_drive_items`, `get_drive_item`, `create_item`, `update_item`, `delete_item`); three are discovery tools (`list_drives`, `list_sites_and_groups`, `search_items`) and stay unguarded.
5. **Code:** the argument allowlist template, with `KEYED_ARG = "drive_id"` and the discovered IDs filled in.
6. **Tests** (via `test_gateway_middleware`, all using un-prefixed `toolName`):
   - allowlisted drive on `list_drive_items` → `allow`
   - non-allowlisted drive on same → `block` with reason `drive_id <id> is not in the allowlist`
   - `list_sites_and_groups` (unguarded) → `allow`
7. **Save:** `admin__create_gateway_middleware` with `phase: "pre"`, `onError: "block"`. Attach **and enable enforcement** via the returned `editUrl`.
8. **Live verify:** call the tool through the actual MCP from the client (e.g. `sharepoint__list_drive_items`) once with an allowed drive and once with a denied drive. The denied one should surface the block reason as the error message.

## Things to watch for

- **`ctx.toolName` is the un-prefixed target tool name, not the client-facing prefixed one.** Clients calling through the gateway see `sharepoint__list_drive_items`, but the middleware sees `list_drive_items`. `admin__list_mcp_tools` shows the client-facing names — strip the connector prefix (everything before and including the first `__`) when populating `GUARDED_TOOLS`. To verify the exact value the runtime is passing, check `admin__query_mcp_logs` — the `toolName` field there matches what `ctx.toolName` will see.
- **Don't guard the discovery path.** If you allowlist drives but also block `list_drives`, the user has no way to find new IDs — you've trapped them.
- **`ctx.arguments` may be undefined.** Use optional chaining (`ctx.arguments?.foo`).
- **`ctx.result` is post-phase only.** Reading it pre-phase returns undefined.
- **`onError: "block"` is fail-closed.** Use it when the rule is security-critical. Use `"allow"` when the middleware is best-effort (e.g. logging, soft warnings).
- **Secrets aren't set via the MCP.** Anything that uses `ctx.secrets.X` must be configured at `editUrl` in the browser before the middleware will work.
- **Saving to Mint is a shared-infra write.** Even if the user said "save it" upfront, Mint's permission layer may prompt — that's expected, not a bug.
