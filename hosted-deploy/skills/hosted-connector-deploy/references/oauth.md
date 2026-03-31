# OAuth on MintMCP Hosted

MintMCP can implement OAuth for your hosted connector, handling the full OAuth
flow (authorization, token exchange, refresh). The MCP server does NOT need to
implement OAuth itself — it just needs to accept access tokens.

## How it works

1. **Connector admin** configures OAuth in the MintMCP UI after deployment:
   authorization URL, token URL, client ID/secret, scopes, and mappings from
   token fields to headers or env vars.
2. **Users** authenticate through MintMCP's OAuth flow when connecting.
3. **MintMCP** manages the token lifecycle (exchange, refresh, storage) and
   forwards fresh access tokens to the server on every request.
4. **The server** just reads the access token from a header (HTTP) or env var
   (stdio) — it never sees the OAuth dance.

## What the server needs to do

Accept an access token via:
- **HTTP transport**: a request header (e.g., `Authorization: Bearer <token>`)
- **stdio transport**: an env var (e.g., `ACCESS_TOKEN=<token>`)

The header/env var name is configurable by the connector admin in MintMCP, so the
server just needs to support reading a token from *some* header or env var.

That's it. No authorization endpoints, no redirect URIs, no refresh token logic.

## If the server has built-in OAuth

Strip it out or bypass it. Built-in OAuth flows don't work on MintMCP because the
server is not publicly accessible (redirect URIs won't resolve). Instead:

- Remove or disable the server's own OAuth flow
- Have the server accept a pre-obtained access token via header or env var
- Let MintMCP handle the rest

## Setup sequence

1. Deploy the connector (Dockerfile + hosted-cli) — it does not need OAuth
   working to deploy successfully
2. After deployment, go to the connector settings URL in MintMCP
3. Configure the OAuth settings: authorization URL, token URL, client
   credentials, scopes, and token-to-header/env-var mappings
4. Users can then connect and authenticate through MintMCP's OAuth flow
