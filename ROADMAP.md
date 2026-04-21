# Codex SDLC Wizard Roadmap

## Current State

- `codex-sdlc-wizard@0.3.0` and `v0.3.0` are live
- npm trusted publishing is configured and the GitHub release workflow is wired for OIDC publish
- the repo now ships both a Codex skill package (`SKILL.md`, `agents/openai.yaml`) and the installer/setup adapter (`install.sh`, `setup.sh`)
- release, packaging, npm, skill, setup, adapter, and E2E tests are green

## Next Release Cycle

### 0.3.1

Purpose: prove the trusted-publishing path with a real fresh npm publish instead of a rerun against an already-published `0.3.0`.

Scope:
- bump `package.json` to `0.3.1`
- tag and release `v0.3.1`
- verify GitHub Actions performs the real npm publish through trusted publishing

### 0.4.0

Purpose: finish the biggest remaining Codex-native engineering gap.

Scope:
- issue `#14`
- bridge existing `sdlc` / `adlc` skills into Codex repo discovery
- remove Claude-only review/tool assumptions from the bridged skill text
- add smoke coverage for repo-scope Codex discovery

## Tracker Cleanup

The issue tracker should be updated to match shipped reality after the next proof release.

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

1. Cut `0.3.1`
2. Clean up stale shipped issues
3. Take `#14`
4. Work through `#4` to `#10` as docs/process/product-shape improvements
