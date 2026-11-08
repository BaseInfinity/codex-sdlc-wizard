#!/bin/bash
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' 'codex-cli 0.167.0'
else
    exit 1
fi
