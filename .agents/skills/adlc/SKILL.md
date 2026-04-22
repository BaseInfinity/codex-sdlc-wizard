---
name: adlc
description: Audit / Analysis Development Life Cycle for evidence-heavy, investigation, QA, compliance, and report work. Use when the task depends on gathering evidence, grading claims, or shipping findings rather than only changing code.
argument-hint: [task description]
effort: high
---

# ADLC Skill

## Task

$ARGUMENTS

Use this skill for audit, investigation, evidence collection, compliance framing, deliverable review, or report-generation work.

1. Read `AGENTS.md` first for the base SDLC contract.
2. Separate facts from inference. Label confidence for every outward-facing claim.
3. Prefer direct evidence over memory, assumption, or vague summaries.
4. Capture the exact command, file, screenshot, link, or transcript that supports each finding.
5. If a repeated process defect appears, add a regression check so the same mistake is harder to ship again.
6. Keep deliverables scannable: bullets, headings, exact citations, and clear next actions.
7. Verify screenshots and files after capture using Codex's normal image or file-reading flow. Do not cite unseen artifacts.
8. When code quality and evidence quality both matter, run SDLC and ADLC together.
9. Self-review for overclaiming, missing evidence, stale screenshots, and methodology leaking into user-facing docs.
10. Present a final summary with findings, evidence, verification steps, and residual uncertainty.

## Codex-Native Notes

- Use Codex's normal review flow; do not assume slash commands or host-specific tool names exist.
- Keep this skill focused on evidence quality and claim discipline. Let repo docs define the exact domain rules.
