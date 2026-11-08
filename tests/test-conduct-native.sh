#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/test-conduct-upgrade.sh"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; assert sys.version_info >= (3, 11)' >/dev/null 2>&1; then
    echo "SKIP: optional native Codex adapter tests require Python 3.11+"
    exit 0
fi
PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPT_DIR/test-codex-thread.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPT_DIR/test-conduct-native.py"
