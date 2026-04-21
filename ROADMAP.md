# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.3.1` and `v0.3.1` are live
- npm trusted publishing is configured and the GitHub release workflow is now proven for real OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- release, packaging, npm, skill, setup, adapter, and E2E tests are green

## Next Release Cycle

### 0.4.0

Purpose: finish the biggest remaining Codex-native engineering gap.

Scope:
- issue `#14`
- bridge existing `sdlc` / `adlc` skills into Codex repo discovery
- remove Claude-only review/tool assumptions from the bridged skill text
- add smoke coverage for repo-scope Codex discovery

### 0.5.0

Purpose: tighten the remaining docs/process backlog after the Codex discovery bridge lands.

Scope:
- work through `#4` to `#10`
- keep the honest Codex SDLC architecture explicit
- close the loop on confidence reporting, issue filing, and repo-focus guidance

## Tracker Cleanup

The issue tracker should be updated now that the trusted-publishing proof release is live.

- close or rewrite `#11` first-class Codex skill packaging
- close or rewrite `#12` packaging smoke tests
- close or rewrite `#13` README packaging clarity
- review whether `#7` and `#8` should be closed as mostly shipped or narrowed to docs polish

## Remaining Backlog

After `0.3.1` and issue cleanup, the main backlog is:

- `#14` Codex discovery bridge for `sdlc` / `adlc`
- `#4` setup parity for doc-heavy / scaffold repos
- `#5` auth-heavy Windows / WAM / MFA boundary docs
- `#6` capability detector pattern for auth/license-sensitive repos
- `#7` keep the honest Codex SDLC architecture explicit
- `#8` high-confidence slices and explicit confidence reporting
- `#9` prefer direct GitHub issue creation for proven reusable findings
- `#10` repo-focus rule so product work is not derailed by wizard fixes

## Working Order

1. Clean up stale shipped issues
2. Take `#14`
3. Work through `#4` to `#10` as docs/process/product-shape improvements
