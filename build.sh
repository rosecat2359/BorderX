#!/usr/bin/env bash
# BorderX build script — Windows + Linux
set -euo pipefail
cd "$(dirname "$0")/server"

echo "=== Building for current platform ==="
go build -o borderx-panel ./cmd/panel/
echo "Done: borderx-panel"

echo "=== Building for Linux (amd64) ==="
GOOS=linux GOARCH=amd64 go build -o borderx-panel-linux ./cmd/panel/
echo "Done: borderx-panel-linux"

echo ""
echo "Binaries:"
ls -la borderx-panel borderx-panel-linux 2>/dev/null || ls -la borderx-panel
