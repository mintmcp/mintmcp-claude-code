# MintMCP Claude Code Marketplace

MintMCP Marketplace for Claude Code. Contains plugins for monitoring and security of Claude Code agents.

## Overview

This marketplace provides plugins that extend Claude Code with additional functionality, particularly focused on observability, governance, and security.

## Plugins

### Monitor Plugin

The `monitor` plugin adds hooks for observability and governance for Claude Code agents. It provides:

- **PreToolUse hooks**: Monitor tool usage before execution
- **PostToolUse hooks**: Monitor tool usage after execution  
- **UserPromptSubmit hooks**: Monitor user prompts

#### Installation

The monitor plugin is automatically available when this marketplace is configured in your Claude Code setup by enterprise administrators via `managed-settings.json`.

You can also install it manually in Claude Code by

```
/plugin marketplace add mintmcp/mintmcp-claude-code
/plugin install monitor@mintmcp-claude-code
```
And visiting https://app.mintmcp.com/llm to configure the `MINTMCP_URL` environment variable
in your Claude Code setup.

#### Configuration

The monitor plugin requires the `MINTMCP_URL` environment variable to be set. If not configured, it will display a helpful message directing users to [https://app.mintmcp.com/llm](https://app.mintmcp.com/llm) for setup instructions.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Support

For support, contact: support@mintmcp.com
