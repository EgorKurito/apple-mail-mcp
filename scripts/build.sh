#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Building Swift mail-bridge ==="
cd "$ROOT_DIR/swift"
swift build -c release 2>&1
codesign --force --sign - --entitlements mail-bridge.entitlements .build/release/mail-bridge
echo "Swift bridge built: swift/.build/release/mail-bridge"

echo ""
echo "=== Building TypeScript MCP server ==="
cd "$ROOT_DIR"
npm run build
echo "TypeScript server built: build/index.js"

echo ""
echo "=== Build complete ==="
