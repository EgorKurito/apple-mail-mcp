## Goal (incl. success criteria)

Подготовить apple-mail-mcp к публикации в npm как `@egorkurito/apple-mail-mcp`.
Критерии: npm pack содержит все нужные файлы, shebang в index.js, автоопределение binary, postinstall собирает Swift.

## Constraints/Assumptions

- Имя `apple-mail-mcp` занято — используем scoped `@egorkurito/apple-mail-mcp`
- macOS only (os: darwin)
- Node.js 18+
- Swift binary собирается при postinstall

## Key decisions

- Scoped package name: `@egorkurito/apple-mail-mcp`
- Автоопределение binary через `findBinary()` в swift.ts (MAIL_BRIDGE_BIN остаётся как override)
- postinstall.js пропускает сборку если binary уже существует или платформа не macOS
- MIT лицензия

## State
### Done
- package.json обновлён (name, bin, files, keywords, repository, author, license, engines, os, scripts)
- shebang в src/index.ts
- Автоопределение binary в src/bridge/swift.ts
- scripts/postinstall.js создан
- LICENSE (MIT) создан
- README.md создан
- `npm run build` проходит
- `npm pack --dry-run` показывает 20 файлов, 14kB

### Now
Готово к публикации.

### Next
- `npm publish --access public` (с подтверждением пользователя)
- Коммит изменений

## Open questions (UNCONFIRMED if needed)

Нет.

## Working set (files/ids/commands)

- package.json — метаданные npm
- src/index.ts — shebang
- src/bridge/swift.ts — findBinary() автоопределение
- scripts/postinstall.js — сборка Swift при install
- LICENSE — MIT
- README.md — документация
