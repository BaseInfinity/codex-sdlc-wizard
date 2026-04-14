#!/bin/bash
# SessionStart hook — check AGENTS.md exists
# Output: JSON with additionalContext warning if missing, silent if present

if [ ! -f "AGENTS.md" ]; then
  cat << 'EOF'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"WARNING: No AGENTS.md found. SDLC enforcement requires AGENTS.md. Run install.sh to set up."}}
EOF
fi
