# MintMCP Claude Code Marketplace

MintMCP Marketplace for Claude Code. Contains plugins for monitoring and security of Claude Code agents.

## Overview

This marketplace provides plugins that extend Claude Code with additional functionality, particularly focused on observability, governance, and security.

## Plugins

### Monitor Plugin

The `monitor` plugin adds hooks for observability and governance for Claude Code agents. It provides:

- **PreToolUse hooks**: Monitor tool usage before tool execution
- **PostToolUse hooks**: Monitor tool usage after tool execution  
- **UserPromptSubmit hooks**: Monitor user prompts

#### Installation

The monitor plugin is automatically available when this marketplace is configured in your Claude Code setup by enterprise administrators via `managed-settings.json`.

You can also install it manually in Claude Code by

```
/plugin marketplace add mintmcp/mintmcp-claude-code
/plugin install monitor@mintmcp-claude-code
```

And visiting https://app.mintmcp.com/monitor/setup to configure the `MINTMCP_ORG_KEY` environment variable
in your Claude Code setup.

#### Configuration

The monitor plugin requires the `MINTMCP_ORG_KEY` environment variable to be set. If not configured, it will display a helpful message directing users to [https://app.mintmcp.com/monitor/setup](https://app.mintmcp.com/monitor/setup) for setup instructions.

### Monitor Plugin (Windows)

The `monitor-windows` plugin is the Windows equivalent of the `monitor` plugin, using PowerShell instead of shell scripts. It provides the same functionality:

- **PreToolUse hooks**: Monitor tool usage before tool execution
- **PostToolUse hooks**: Monitor tool usage after tool execution
- **UserPromptSubmit hooks**: Monitor user prompts

#### Installation

```
/plugin marketplace add mintmcp/mintmcp-claude-code
/plugin install monitor-windows@mintmcp-claude-code
```

And visiting https://app.mintmcp.com/monitor/setup to configure the `MINTMCP_ORG_KEY` environment variable in your Claude Code setup.

#### Configuration

Same as the Unix monitor plugin — requires the `MINTMCP_ORG_KEY` environment variable. Optionally set `MINTMCP_USER` (defaults to `%USERNAME%`) and `MINTMCP_BASE_URL`.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Support

For support, contact: support@mintmcp.com
