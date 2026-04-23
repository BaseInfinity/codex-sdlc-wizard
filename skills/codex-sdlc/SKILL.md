---
name: codex-sdlc
description: Full SDLC workflow for Codex. Use when implementing features, fixing bugs, refactoring, testing, or reviewing work that needs planning, TDD, proof, and self-review.
---

# Codex SDLC

## Purpose

This is the Codex-native SDLC workflow skill. It is the honest equivalent of a missing `/sdlc` command.

Use it for:

- features
- bug fixes
- refactors
- testing work
- risky reviews
- shipping slices that need real proof

## Mandatory first action

Before doing anything else, read the repo-local contract when present:

- `AGENTS.md`
- `README.md`
- `ROADMAP.md`
- `SDLC-LOOP.md`
- `START-SDLC.md`
- `PROVE-IT.md`
- `TESTING.md`
- `ARCHITECTURE.md`

Repo-local guidance wins over generic skill guidance.

## Full workflow

### 1. Planning

For meaningful work, make these visible before implementation:

- task
- scope
- confidence
- verification plan

Check:

- what docs or specs matter
- what patterns already exist
- blast radius
- whether a new pattern is actually needed
- whether the test approach matches `TESTING.md`

Before implementation, do a docs update for the relevant feature area when the code change affects behavior, assumptions, or operator workflow.

### 2. TDD

Prefer:

1. red
2. green
3. prove-it

If strict test-first is not realistic for the very first primitive or baseline slice, say so explicitly and get back to TDD as soon as the baseline exists.

### 3. Prove-it

Before commit or handoff, run the broader checks that matter for the slice.

In this ecosystem, `prove-it` often matters more than unit success because:

- hooks can block risky git actions
- mocks can lie
- Graph, COM, browser, and tenant behavior often need integration proof

### 4. Self-review

Read back what changed and check for:

- scope creep
- dead code
- fake confidence from mocks
- missing docs
- missing verification

### 5. CI and Merge Guard

Never use auto-merge in this repo.

`NEVER AUTO-MERGE`

Read CI logs, handle valid review feedback, and merge explicitly only after the proof matches the diff.

### 6. Final summary

Before handoff, make these visible:

- what changed
- what was verified
- what is still risky or unverified

### 7. Capture Learnings

If the session uncovered reusable lessons, capture learnings in the right local doc:

- `TESTING.md` for testing lessons
- feature docs for feature-specific behavior
- `ARCHITECTURE.md` for architecture decisions
- `README.md` or repo-local workflow docs when the user-facing setup story changed

## Confidence policy

- default: `xhigh`
- this repo uses `xhigh` as the normal path
- only drop lower when the user explicitly asks for it

## Hooks vs skill

- hooks are silent, event-driven enforcement
- this skill is the user-facing workflow layer
- do not pretend Codex has a native `/sdlc` command if it does not

## Quality bar

- keep changes small and coherent
- prefer boring correctness over cleverness
- do not commit what you did not prove
