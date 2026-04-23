---
name: feedback
description: Privacy-first feedback loop for Codex SDLC wizard usage — capture bugs, feature requests, patterns, and improvements without scanning code unless the user explicitly allows it.
---

# Feedback

## Purpose

Help the user contribute back to the Codex SDLC wizard:

- bug reports
- feature requests
- working patterns
- process improvements

Privacy first. Never scan the repo without explicit permission.

## Mandatory permission rule

Before scanning anything beyond obvious SDLC file names, ask first.

Use this exact shape when asking:

> "I can scan your SDLC setup to identify what you've customized versus wizard defaults. This helps me create a more specific report. May I scan? Only SDLC file names and config are read - no source code, secrets, or business logic."

Only scan:

- repo-local SDLC docs
- hook file names and which hooks are active
- skill names and which skills exist
- high-level config related to SDLC setup

Never scan:

- source code
- secrets
- `.env`
- proprietary business logic
- unrelated repo content

## Feedback types

### Bug report

- capture the issue
- identify the SDLC surface involved
- record reproduction steps

### Feature request

- capture the desired behavior
- check whether the current wizard already has a nearby capability
- describe the gap cleanly

### Pattern sharing

- capture what the user changed
- identify why it worked
- separate generic lessons from project-specific quirks

### Improvement

- capture what part of the SDLC flow is weak
- explain whether the problem is skill, hook, docs, install, or ecosystem mismatch

## Output shape

When preparing feedback, include:

- feedback type
- concise description
- local context
- evidence
- what should change

## Rules

- Ask before scanning.
- Check for duplicates before proposing a new issue or feedback item.
- Keep it specific.
- No source code by default.
- Prefer reusable lessons over one-off complaints.
