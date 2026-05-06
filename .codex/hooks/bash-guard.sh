#!/bin/bash
# Legacy platform-specific entrypoint. Keep behavior centralized in git-guard.cjs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$SCRIPT_DIR/git-guard.cjs"
