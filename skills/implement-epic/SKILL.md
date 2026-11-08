---
name: implement-epic
description: Drive an epic from idea to merged PRs — plan it with plan-epic, wait for the plan's approval, then implement its phases with sub-agents (implement-phase), review each one (review-pr) and prepare its PR (propose-pr), continuing with the next phases once the user merges. Use when asked to implement, run, or continue a whole epic (e.g. "/implement-epic add_feature", "implement this feature as an epic"). For a single phase use implement-phase.
---

# Implement Epic

Orchestrates an epic using the [plan-epic](../plan-epic/SKILL.md), [implement-phase](../implement-phase/SKILL.md), [review-pr](../review-pr/SKILL.md) and [propose-pr](../propose-pr/SKILL.md) skills.

The skill is **resumable**: every run works out the current state (Step 2) and does the next possible steps. Run it again to continue (locally after you committed, in a web session when a PR event arrives).

**Roles:**

- **Main agent** (you, the session model, Opus by default): plans, reviews, talks to the user, pushes and opens PRs.
- **Phase agents**: one sub-agent per phase, started with `model: "sonnet"`, each in its own git worktree.

## Rules

- **Only the user merges.** Never approve or merge a PR.
- **One commit per phase.** Fixes are amended into it, so a phase can be rebased easily when an earlier phase changes.
- **Force-push only phase branches.** You may rebase and `git push --force-with-lease` your own `epic/<feature>/phase-<N>` branches, nothing else. If force-pushing is not possible (denied, local mode), ask the user to rebase.
- **Local mode:** no authenticated git or GitHub commands: no `push`, no `gh`, no commits. The user commits (signed), pushes and opens PRs.
- At most **3** phase agents at a time.
- After each step, show the user a short status table: phase → status → branch/PR.

## Step 1 — Setup

1. **Detect the mode:**
   - **Web**: `CLAUDE_CODE_REMOTE=true` and you can push and use GitHub tools (create PRs, subscribe to PR activity).
   - **Local**: anything else.
2. **Ask once** (one question, skip what this conversation already settled):
   - Confirm the detected mode.
   - **PR strategy**:
     - **Merge each**: every phase PR targets `main`. A phase starts once the phases it depends on are merged. Independent phases run in parallel.
     - **Stacked**: every phase PR targets the previous phase's branch. Phases run one after another. The next phase starts once the previous one passed review (web) or was committed by the user (local), without waiting for a merge.
   - Web: confirm you may push branches named `epic/<feature>/plan` and `epic/<feature>/phase-<N>`.
3. Record the strategy in the epic file's header (`PR strategy: merge each` / `PR strategy: stacked`). If an epic already exists and has it, don't ask again.

## Step 2 — Determine the state

1. Find the epic file under `epics/` (on `main`, or in an open PR / `epic/<feature>/plan` branch).
2. If there is none → Step 3. If it is not on `main` yet → the plan awaits approval: tell the user and stop.
3. Otherwise build the phase status table as described in implement-phase Step 2. Statuses: `not started`, `in progress` (branch or worktree exists, no PR), `in review` (PR open), `merged`.
4. Pick the phases to start now:
   - **Merge each**: `not started` phases whose dependencies are `merged`.
   - **Stacked**: the first `not started` phase, if the phase below it is reviewed (web: PR open) or committed (local).
5. Nothing to start and nothing in progress → if every phase is merged, go to Step 7; else tell the user what you are waiting for and stop.

## Step 3 — Plan the epic

1. Use plan-epic with the user's information. Ask about anything unclear before writing.
2. For every phase, state **Depends on:** (phases) and whether it **can run in parallel** with others.
3. Add the PR strategy line (Step 1).
4. Propose the plan:
   - **Web**: commit to `epic/<feature>/plan`, push, open a PR (title and description from propose-pr), subscribe to its activity. Address review comments yourself.
   - **Local**: leave the change uncommitted. Show the propose-pr title and description, and ask the user to commit (signed), push and open the PR.
5. **Stop.** No phase starts before the user merged the plan PR.

## Step 4 — Start the phase agents

For each phase picked in Step 2:

1. Base: `main` (merge each) or the previous phase's branch (stacked).
2. Start a sub-agent with `model: "sonnet"` and `isolation: "worktree"`. If worktree isolation is not available, create one yourself: `git worktree add ../<repo>-phase-<N> -b epic/<feature>/phase-<N> <base>`. Run parallel phases in the background.
3. Prompt:

   ```
   Use the implement-phase skill to implement phase <N> of <epic file>.
   Branch: epic/<feature>/phase-<N>, based on <base>. Work only in your worktree: <path>.
   Do not ask the user. If you need a decision (e.g. size over budget, unclear spec), stop and report the question.
   <Web:   Commit your change as a single commit (message in the repository's style). Do not push.>
   <Local: Do not commit.>
   Report the implement-phase summary and the worktree path.
   ```

4. If a phase agent reports a question, ask the user and send the answer back to that agent (SendMessage).

## Step 5 — Review and propose

When a phase agent is done:

1. In its worktree, run review-pr with `--base <base>`. Local: it reviews the uncommitted changes.
2. If there are 🔴 or 🟠 findings, send them to the phase agent to fix (web: amend the phase commit), then review again. After 2 rounds, ask the user how to proceed.
3. Then:
   - **Web**: push the branch, open the PR against `<base>` (title and description from propose-pr), subscribe to its activity. Stacked: continue with Step 2 to start the next phase.
   - **Local**: show the user the worktree path, the review result, the propose-pr title and description, and a commit message. Ask them to review, commit (signed), push and open the PR, then run this skill again.

## Step 6 — Follow the PRs (web)

On PR activity:

- **Review comments or failing CI** → send them to the phase agent to amend the phase commit. If it is gone (e.g. after a restart), start a new phase agent (`model: "sonnet"`) in that branch's worktree with the comments and the phase. Review its changes (Step 5.1) before force-pushing.
- **Merged** → go to Step 2 and start the phases that are now unblocked.
- **Stacked, a lower PR changed** → rebase each branch above it onto its updated parent, bottom up (`git rebase --onto <parent branch> <old parent commit>`), resolve conflicts, force-push. If the user merged a lower PR, rebase the next branch onto `main` and retarget its PR to `main`.

## Step 7 — Finish

The final phase removes the epic file (implement-phase Step 6). Once it is merged:

1. Remove the worktrees you created (`git worktree remove <path>`), only if they are clean.
2. Report the final status table with all PRs.
