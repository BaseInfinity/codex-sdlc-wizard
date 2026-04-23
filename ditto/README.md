# Ditto

Placeholder for a future cross-host migration tool.

Intent:

- detect an existing agent setup in a repo
- extract the portable SDLC intent
- translate hooks, skills, and docs between hosts such as Claude, Codex, and later other adapters
- preserve user customizations with a scan -> plan -> backup -> apply -> verify flow

Why this is separate from `codex-sdlc-wizard`:

- `codex-sdlc-wizard` should stay focused on the Codex-native install/setup/update/check path
- host-to-host migration is a different product surface with a different abstraction boundary
- keeping it separate avoids turning this repo into an adapter kitchen sink

Status:

- idea captured
- no code or release surface yet
