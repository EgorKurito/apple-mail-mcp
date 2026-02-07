# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Apple Mail MCP server — MCP сервер для Apple Mail через NSAppleScript автоматизацию. Двухслойная архитектура: TypeScript MCP server вызывает Swift CLI binary (`mail-bridge`) через execa. Read-only доступ к почте: аккаунты, папки, сообщения, поиск.

## Build & Run

```bash
# Полная сборка (Swift + TypeScript)
./scripts/build.sh

# Только Swift bridge
cd swift && swift build -c release && codesign --force --sign - --entitlements mail-bridge.entitlements .build/release/mail-bridge

# Только TypeScript
npm run build    # tsc -> build/

# Проверка Swift binary
swift/.build/release/mail-bridge mail-doctor
swift/.build/release/mail-bridge mail-accounts
swift/.build/release/mail-bridge mailboxes
swift/.build/release/mail-bridge messages --mailbox INBOX --account Google --limit 5
swift/.build/release/mail-bridge message-detail --id 12345 --mailbox INBOX --account Google
swift/.build/release/mail-bridge unread-messages --limit 10
swift/.build/release/mail-bridge search-mail --query "invoice" --limit 10
```

Тестов нет. Верификация — ручная через CLI команды и MCP inspector.

## Architecture

```
Claude Code --stdio JSON-RPC--> TypeScript MCP Server --execa--> Swift CLI (mail-bridge) --NSAppleScript--> Mail.app
```

**TypeScript layer** (`src/`):
- `index.ts` — McpServer с StdioServerTransport, читает `MAIL_BRIDGE_BIN` env var
- `bridge/swift.ts` — SwiftBridge class: вызывает binary через execa, парсит JSON envelope `{status, data, error}`, timeout 60s
- `tools/mail.ts` — 6 MCP tools с Zod-валидацией: get_mail_accounts, get_mailboxes, get_messages, get_message, get_unread_messages, search_mail

**Swift layer** (`swift/Sources/MailBridge/`):
- `main.swift` — ArgumentParser CLI с 7 субкомандами (mail-doctor + 6 MCP tools)
- `MailService.swift` — NSAppleScript вызовы к Mail.app; batch property access для производительности; delimiter-based парсинг результатов
- `Models.swift` — Encodable DTOs, BridgeOutput<T> JSON envelope, BridgeError enum, parseSender() helper

**Ключевое**:
- Все данные через AppleScript — нет нативного API для Mail (как EventKit для Calendar)
- `line` — зарезервированное слово AppleScript, используем `rowData` вместо
- Разделители: `|||` между записями, `:::` между полями, `;;;` между подполями, `~~~` между полями вложений

## Important Conventions

- **stdout зарезервирован для MCP JSON-RPC** — в TypeScript использовать только `console.error()` для логов
- **Swift CLI всегда возвращает JSON envelope**: `{"status":"ok","data":...}` или `{"status":"error","error":"..."}`
- **ESM модули**: package.json `"type": "module"`, импорты с `.js` расширением
- **Swift**: флаг `-parse-as-library` в Package.swift обязателен для @main + ArgumentParser
- **TCC permissions**: binary должен быть подписан с entitlements для Automation Apple Events
- **MAIL_BRIDGE_BIN** — единственный способ передать путь к Swift binary в MCP server
- **Timeout 60s** для mail-bridge (медленнее чем calendar)
- **Лимит 50 по умолчанию, 200 максимум** для пагинации сообщений

## MCP Integration

Через `.mcp.json` в проекте-потребителе или `claude mcp add --scope user`:
```json
{
  "mcpServers": {
    "apple-mail": {
      "command": "node",
      "args": ["/path/to/build/index.js"],
      "env": { "MAIL_BRIDGE_BIN": "/path/to/swift/.build/release/mail-bridge" }
    }
  }
}
```

## Troubleshooting

- **Mail.app access denied (-1743)**: System Settings > Privacy & Security > Automation > разрешить mail-bridge управлять Mail.app
- **Пустые результаты**: убедиться что Mail.app запущен и аккаунт подключён
- **AppleScript reserved words**: `line` зарезервировано, использовать `rowData`
- **Медленные запросы**: уменьшить limit, указать конкретный account/mailbox
