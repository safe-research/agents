---
name: propose-pr
description: Draft a pull request title and description for the current changes by filling in the repo's .github/pull_request_template.md. Only invoke when explicitly asked (e.g. "/propose-pr") — never automatically after making changes.
---

# Propose PR

Produce a PR title and a filled-in PR description for the current changes. Output only — do not create or push anything (no `gh pr create`, no commits) unless the user explicitly asks for that separately.

## Step 1 — Gather the changes

Determine what changes to consider, in this order of preference:

1. If the worktree is dirty (`git status --porcelain`), use the dirty diff: `git diff` (unstaged) and `git diff --staged` (staged), plus untracked files relevant to the change.
2. Otherwise, diff the current branch against its immediate parent (e.g. `git merge-base main HEAD` then `git diff <merge-base>..HEAD`, or the equivalent against the branch's actual parent if not `main`).

Also use any context already known from this conversation about what was implemented and why — don't rediscover things you already know.

## Step 2 — Determine the PR title

Run `git log --pretty=oneline -20` (or similar) to see recent commit titles on the branch's history. Match their style, tense, capitalization, and length convention (e.g. imperative mood, "Add X", "Fix Y") when writing the new PR title, so it reads as consistent with recently merged PRs.

If the change implements a phase of an epic plan (see the [plan-epic skill](../plan-epic/SKILL.md), with specifications under `epics/`), include the phase in the title so the PR's place in the epic is obvious — e.g. `[Feature 2] Do Some Stuff` (for feature `Feature` and phase 2). Determine whether or not a change is part of an epic based on existing context (e.g. you were asked to implement a phase from an epic). 

## Step 3 — Load the template

Read `.github/pull_request_template.md` from the repository root. If it doesn't exist, ask the user for the path or whether to proceed without a template (a plain Summary + Testing description).

## Step 4 — Fill in the template

Fill in each section of the template using the actual diff and conversation context. Rules:

- Be succinct, not grandiose. No marketing language, no restating the obvious.
- Do not include information that's already verified by CI or is boilerplate (e.g. "all tests pass", "linting passes"). Only mention testing that's unobvious or specific to this change — e.g. what scenario a new test covers, or an unusual verification method (a temp SQLite DB to check disk persistence, a manual repro against a running server, etc.). If nothing non-obvious was done for testing, prefer removing the section if the template permits, or say so briefly.
- If a section of the template doesn't apply, say "N/A" or omit per the template's own conventions rather than inventing content.
- If the template contains comments (e.g. HTML comments with instructions or placeholders), follow them and then remove them from the final description — the filled-in output must not contain any leftover template comments.
- Keep the description grounded strictly in the actual diff — don't speculate about unrelated future work.

## Output

Output exactly two things, in this order:

1. **PR title** — a single line.
2. **PR description** — the filled-in template, as a markdown code block so it's easy to copy.
