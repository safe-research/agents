---
name: implement-phase
description: Implement a single phase of an epic plan created with the plan-epic skill (a specification file under `epics/`). Use when asked to implement, start, or continue a phase of an epic (e.g. "implement phase 2 of epics/2026_10_01_add_feature.md", "/implement-phase add_feature 3"). Gathers context from earlier phases' commits and PRs, keeps the change reviewable (~300 lines), and — for the final phase — verifies every phase was implemented before removing the epic file.
---

# Implement Phase

Implements exactly one phase of an epic planned with the [plan-epic skill](../plan-epic/SKILL.md). The result MUST be a change that fits into one human-reviewable PR with a single purpose.

**Input:** the epic and the phase to implement, in one of these forms:

- **File reference** (preferred) — `<file>:<line>` or a line range such as `<file>:<start>-<end>` / `<file>#L<start>:<end>` (e.g. `epics/2026_10_01_add_feature.md:42`). The file is the epic; the phase is the one whose section (under `Implementation Phases`) contains the referenced line(s), i.e. the nearest phase heading at or above the line. If the lines fall outside `Implementation Phases` or span more than one phase, list the candidate phases and ask.
- **Epic + phase** — a path to the specification file or a name fragment (resolved against `epics/` at the repository root), plus a phase number or title. If nothing or several files match, list the candidates and ask.
- **Epic only** — determine the next unimplemented phase (Step 2) and confirm it with the user before writing code.

Additional free text from the user (constraints, corrections, hints) is authoritative. If it conflicts with the epic or with what earlier phases did, surface the conflict instead of silently picking a side.

## Step 1 — Read the epic and the repository guidelines

1. Read the full epic file, not just the phase: the architecture decision, tech specs, and open questions/assumptions constrain how the phase is implemented.
2. Read `AGENTS.md` / `CLAUDE.md` (and the docs they link to) for coding, testing, and formatting guidelines. Follow them.
3. Note what the phase says it will touch: flows, files, components. Also note whether it is marked as parallelizable with other phases or depends on earlier ones.

## Step 2 — Gather context from earlier work on the epic

Earlier phases were implemented in separate PRs, and their reality may differ from the plan. Find out what was actually done before writing any code.

Epics are normally developed as a **PR stack**: one PR per phase, each based on the previous phase's branch, merged together at the end. The current branch is expected to be the tip of that stack (the previous phase), and the new phase is built on top of it.

1. **Stack commits** — list the epic's commits, i.e. everything on top of `main`, oldest first:

   ```sh
   git log --reverse --format='%H %s' origin/main..HEAD
   ```

   Read the full messages and diffs (`git show <sha>`) of these commits; they are the earlier phases.
2. **Stack PRs** — match those commits to their open PRs with a single unauthenticated request to the GitHub REST API (no `gh`, no token, no pagination):

   ```sh
   # owner/repo from the remote, e.g. git@github.com:safe-research/safenet.git -> safe-research/safenet
   repo=$(git remote get-url origin | sed -E 's#(\.git)?/?$##; s#^.*github\.com[:/]##')
   curl -sf "https://api.github.com/repos/$repo/pulls?state=open&per_page=100" \
     | jq '[.[] | {number, title, sha: .head.sha, branch: .head.ref, base: .base.ref, url: .html_url, body}]'
   ```

   A PR belongs to the stack if its `sha` is one of the stack commits; the commits between it and the previous PR's head belong to it as well. If a SHA does not match (e.g. local commits not pushed yet), match by `branch` against `git branch -a --points-at <sha>` instead, and treat unmatched commits as not yet proposed. Read the PR bodies: they often record decisions and deviations from the plan that apply to this phase too. If the request fails, continue with the commit messages and say so in the summary.
3. **Not a stack** — if there are no commits on top of `main` (e.g. earlier phases were merged individually), check the commit history of `main` instead (`git log -- <epic file>`, `git log -i --grep "<Feature>"`, `git log -- <files the epic mentions>`). Squash-merged PRs have their title and description as commit message, so no PR lookup is needed.
4. **Existing work for this phase** — if a commit, PR, or branch for the requested phase already exists, stop and ask the user whether to continue that work or start fresh.
5. Build a short status table: phase → status (in stack / merged to `main` / not started) → PR or commit reference. Use it to:
   - Check that phases this one depends on are implemented below it in the stack or on `main`. If not, tell the user and ask whether to proceed.
   - Identify deviations between the plan and what was implemented (renamed components, moved files, changed approach). Implement this phase against the **actual** code, and list the deviations you had to account for in the final summary.

## Step 3 — Plan the change and estimate its size

Before writing code, outline the concrete edits (files, new modules, tests) and estimate the size of the diff.

**Size budget:** the change SHOULD NOT majorly exceed **~300 changed lines** (additions + deletions) and SHOULD touch fewer than 10 files. The goal is a PR a human can review in one sitting with little context. Judge by the kind of change, not by a raw line count:

- Count hand-written source and test code at full weight.
- Lock files, generated code, snapshots, and vendored files do not count.
- Mechanical changes weigh less: scaffolding (boilerplate from a generator or template), pure deletions of files/code, renames, and large static fixtures may legitimately exceed the budget.
- A small change spread over many files can still be hard to review — consider the file count too.

If the estimate clearly exceeds the budget for reviewable code, **stop and ask the user** before implementing, using AskUserQuestion with these options:

1. **Propose a split** — you investigate how to split the phase into smaller, independently mergeable steps (e.g. extract a preparatory refactor, land types/interfaces first, separate tests for an existing component) and present the proposal. Do not implement until the user picks a split.
2. **Exceed the limit** — implement the phase as one change. Include the reason (e.g. scaffolding, removal) in the final summary so it can go into the PR description.

Include the estimate and its breakdown (which files, roughly how many lines, which parts are mechanical) in the question so the user can decide without further digging.

If the phase is too large due to an issue in the plan itself, mention that the epic file could be updated with the split; only edit the epic file if the user agrees.

## Step 4 — Implement

- Implement only what this phase describes. Do not pull in work from later phases, and do not mix in unrelated refactoring, formatting, or dependency updates. If you find something that should be fixed, list it in the summary as a follow-up.
- Add or update tests according to the repository's testing guidelines and the phase's test cases from the epic's tech specs.
- Run the repository's formatter, linter, and tests for the touched component (see `AGENTS.md`, `Justfile`, `package.json`, `Cargo.toml`, etc.). Fix failures caused by your change.
- Do not edit the epic file as part of a regular phase unless the user asked for it (exception: the final phase, Step 6).

## Step 5 — Check the actual size

Measure only this phase's diff, including untracked files. The base is the tip of the stack before this phase (the previous phase's commit), not `main`:

```sh
base=<previous phase's commit>            # = HEAD before starting this phase; merge-base with origin/main if not a stack
git diff --numstat "$base"                # tracked changes (committed and uncommitted)
git ls-files --others --exclude-standard | xargs -r wc -l   # new, untracked files
```

Apply the same weighting as in Step 3. If the change ended up majorly over the budget even though the estimate was not (or the user did not already approve exceeding it), stop and ask the user again with the same two options before finalizing. Do not silently trim tests or behavior to get under the limit.

## Step 6 — Final phase: verify the epic and remove the plan

The plan-epic skill requires the last phase to remove the epic file. Before deleting it, verify that the epic is actually complete:

1. Using the status table from Step 2, confirm every other phase is implemented — in the stack below this phase or already on `main`. Missing phases block removal.
2. For each phase, spot-check the code at the current `HEAD` against the phase description: the listed components/files/routes/env vars exist, the described flows are covered, and the test cases from the tech specs are present. Check that nothing the plan marked as temporary (feature flags, compatibility shims, TODOs referencing the epic) is left behind.
3. Check the epic's `Open Questions and Assumptions` for items that were never resolved.
4. Grep the repository for references to the epic file (links in docs, code comments) and remove or update them in this change.

Report the result as a per-phase checklist. If anything is missing or doubtful, **do not delete the epic file** — present the gaps and ask the user how to proceed (implement the gap first, accept the deviation, or remove anyway). Only remove the file once every phase is verified or the user explicitly accepts the remaining gaps.

## Output

Do not commit, push, or open a PR unless the user asks. Finish with a short summary:

- The phase implemented and the epic it belongs to.
- The phase status table (from Step 2) — for the final phase, the verification checklist (from Step 6).
- Deviations from the plan that this phase had to account for, or introduced.
- The measured diff size, and if over budget, why that was accepted.
- Follow-ups noticed but deliberately left out.
- A suggestion to run `/propose-pr` to draft the PR description.
