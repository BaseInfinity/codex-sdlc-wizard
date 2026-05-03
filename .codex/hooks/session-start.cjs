#!/usr/bin/env node
const fs = require("node:fs");

if (!fs.existsSync("AGENTS.md")) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: "WARNING: No AGENTS.md found. SDLC enforcement requires AGENTS.md. Run install.sh to set up."
    }
  }));
}
