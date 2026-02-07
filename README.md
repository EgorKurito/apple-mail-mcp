# @egorkurito/apple-mail-mcp

MCP server for Apple Mail on macOS. Provides read-only access to mail accounts, mailboxes, and messages through the [Model Context Protocol](https://modelcontextprotocol.io).

Uses a two-layer architecture: TypeScript MCP server communicates with a Swift CLI binary (`mail-bridge`) that interfaces with Mail.app via NSAppleScript.

## Requirements

- **macOS 13+** (Ventura or later)
- **Node.js 18+**
- **Xcode Command Line Tools** (`xcode-select --install`)
- **Mail.app** configured with at least one account

## Installation

### Claude Desktop / Claude Code

Add to your MCP configuration:

```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "npx",
      "args": ["-y", "@egorkurito/apple-mail-mcp"]
    }
  }
}
```

### Global install

```bash
npm install -g @egorkurito/apple-mail-mcp
```

Then configure MCP:

```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "apple-mail-mcp"
    }
  }
}
```

### Manual (with custom binary path)

```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "node",
      "args": ["/path/to/build/index.js"],
      "env": {
        "MAIL_BRIDGE_BIN": "/path/to/swift/.build/release/mail-bridge"
      }
    }
  }
}
```

## Available Tools

| Tool | Description |
|------|-------------|
| `get_mail_accounts` | List all mail accounts (name, email, type, enabled) |
| `get_mailboxes` | List mailboxes with unread/message counts and nested folders |
| `get_messages` | Get message headers from a mailbox with pagination (newest first) |
| `get_message` | Get full message content including body, recipients, and attachments |
| `get_unread_messages` | List unread messages across all accounts or filtered by account/mailbox |
| `search_mail` | Search messages by subject or sender |

## Permissions

On first run, macOS will ask you to grant automation permissions. Go to:

**System Settings > Privacy & Security > Automation** and allow `mail-bridge` (or Terminal/iTerm) to control **Mail.app**.

## Troubleshooting

**"Mail.app access denied" (-1743)**
Grant automation permissions in System Settings > Privacy & Security > Automation.

**Empty results**
Make sure Mail.app is running and at least one account is connected.

**Swift build fails during install**
Ensure Xcode Command Line Tools are installed: `xcode-select --install`

**Slow queries**
Reduce the `limit` parameter or specify a specific `account`/`mailbox` to narrow the search.

## License

MIT
