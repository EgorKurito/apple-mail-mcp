# apple-mail-mcp

MCP server for Apple Mail. Provides read-only access to mail accounts, mailboxes, and messages via NSAppleScript automation.

Unlike AppleScript-based alternatives, this server uses a **Swift CLI bridge** with proper macOS code signing and Automation entitlements, delivering structured JSON output with parsed sender information, nested mailbox hierarchies, and paginated message access.

## Architecture

```
Claude Code ↔ MCP (stdio) ↔ TypeScript Server ↔ Swift CLI Bridge ↔ NSAppleScript ↔ Mail.app
```

The Swift bridge (`mail-bridge`) executes AppleScript commands in-process via `NSAppleScript`, which is faster than spawning `osascript` subprocesses. Results are returned as structured JSON through a `{status, data, error}` envelope protocol.

## Prerequisites

- macOS 13+
- Swift 5.9+
- Node.js 20+
- Apple Mail configured with at least one account

## Build

```bash
# Build everything (Swift + TypeScript + codesign)
./scripts/build.sh

# Or separately:

# Swift bridge
cd swift
swift build -c release
codesign --force --sign - --entitlements mail-bridge.entitlements .build/release/mail-bridge

# TypeScript server
npm install
npm run build
```

## Grant Mail Access

The first run triggers a macOS permission prompt:

> "mail-bridge" wants to control "Mail.app"

Click **OK** to allow.

You can verify access with:

```bash
swift/.build/release/mail-bridge mail-doctor
```

If access was denied, go to **System Settings > Privacy & Security > Automation** and enable `mail-bridge → Mail.app`.

## Connect to Claude Code

### Option A: Project-level `.mcp.json`

Copy `.mcp.json.example` to `.mcp.json` in your project and update paths:

```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "node",
      "args": ["/path/to/apple-mail-mcp/build/index.js"],
      "env": {
        "MAIL_BRIDGE_BIN": "/path/to/apple-mail-mcp/swift/.build/release/mail-bridge"
      }
    }
  }
}
```

### Option B: CLI registration (user-wide)

```bash
claude mcp add -s user apple-mail \
  -e MAIL_BRIDGE_BIN=/path/to/apple-mail-mcp/swift/.build/release/mail-bridge \
  -- node /path/to/apple-mail-mcp/build/index.js
```

## MCP Tools

| Tool | Description |
|------|-------------|
| `get_mail_accounts` | List all mail accounts (name, email, type, enabled) |
| `get_mailboxes` | List mailboxes with unread/message counts and nested folders |
| `get_messages` | Get message headers from a mailbox with pagination (newest first) |
| `get_message` | Get full message content including body, recipients, and attachments |
| `get_unread_messages` | List unread messages across all accounts or filtered |
| `search_mail` | Search messages by subject or sender |

### Tool Parameters

**get_mailboxes**
- `account` (optional) — filter by account name

**get_messages**
- `mailbox` (required) — mailbox name (e.g. `INBOX`)
- `account` (optional) — account name
- `limit` (optional) — max messages, default 50, max 200
- `offset` (optional) — offset from newest, default 0

**get_message**
- `id` (required) — message ID (from `get_messages`)
- `mailbox` (required) — mailbox name
- `account` (optional) — account name

**get_unread_messages**
- `account` (optional) — filter by account
- `mailbox` (optional) — filter by mailbox
- `limit` (optional) — max messages, default 50, max 200

**search_mail**
- `query` (required) — search text (matches subject and sender)
- `account` (optional) — filter by account
- `mailbox` (optional) — filter by mailbox
- `limit` (optional) — max results, default 50, max 200

## CLI Reference

The Swift bridge can be used standalone:

```bash
# Diagnostics
mail-bridge mail-doctor

# List accounts
mail-bridge mail-accounts

# List mailboxes
mail-bridge mailboxes
mail-bridge mailboxes --account "Gmail"

# List messages (newest first, paginated)
mail-bridge messages --mailbox INBOX --account "Gmail" --limit 10

# Full message content
mail-bridge message-detail --id 12345 --mailbox INBOX --account "Gmail"

# Unread messages
mail-bridge unread-messages --limit 10
mail-bridge unread-messages --account "Gmail" --mailbox INBOX

# Search
mail-bridge search-mail --query "invoice" --limit 20
mail-bridge search-mail --query "meeting" --account "Gmail"
```

## Data Models

**MailAccountInfo** — id, name, fullName, emailAddresses, accountType (iCloud/imap/exchange), enabled

**MailboxInfo** — name, fullName (account/path), account, unreadCount, messageCount, children (nested)

**MailMessageHeader** — id, messageId, subject, sender, senderName, senderEmail, dateSent, dateReceived, isRead, isFlagged, hasAttachments, mailbox, account

**MailMessageDetail** — all header fields + toRecipients, ccRecipients, content (plain text), attachments

**MailAttachmentInfo** — name, mimeType, fileSize

## Troubleshooting

**"Mail.app access denied" / error -1743**
- System Settings > Privacy & Security > Automation
- Enable `mail-bridge` access to `Mail.app`

**Empty results**
- Make sure Mail.app is running and has at least one configured account
- Check `mail-bridge mail-doctor` output

**Slow queries**
- Reduce `limit` parameter
- Specify `account` and `mailbox` to narrow scope
- Large mailboxes (>5000 messages) may take several seconds

**Build fails on codesign**
- The ad-hoc signature (`--sign -`) requires no Apple Developer account
- If you get signing errors, try `codesign --force --sign - --entitlements mail-bridge.entitlements .build/release/mail-bridge`

## How It Works

1. **TypeScript MCP server** receives JSON-RPC requests via stdio
2. Calls **Swift CLI binary** (`mail-bridge`) via `execa` with appropriate subcommand and arguments
3. Swift binary executes **NSAppleScript** commands against Mail.app
4. AppleScript results are parsed using delimiter-based protocol (`|||` between records, `:::` between fields)
5. Structured JSON response returned through `BridgeOutput<T>` envelope

NSAppleScript runs in-process (no subprocess overhead), and batch property access (`subject of messages 1 thru 50`) is used instead of per-message iteration for performance.

## License

MIT
