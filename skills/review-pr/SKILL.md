---
name: review-pr
description: Review the pull request for the currently checked-out branch (e.g. "/review-pr", "/review-pr 42", "review this PR", "can you look over this branch before I approve it"). Considers the changed code, the commit messages, the PR description, a related epic plan under `epics/`, and docs linked from AGENTS.md/CLAUDE.md, then reports a short, prioritized list of verified, actionable findings with links to exact lines. Works without a GitHub token or authenticated git, locally and inside a GitHub Actions workflow. Use whenever the user asks to review, audit, or sanity-check a PR or the current branch's changes — not for addressing review comments on your own PR (use handle-pr-comments) and not for reviewing uncommitted local changes.
---

# Review PR

Review the pull request of the checked-out branch and report **only actionable, verified findings about the changed code**, ordered by priority and linked to exact lines. A short review that catches the one real bug is far more valuable than a long one that buries it among nitpicks — every finding costs the reader attention, so each one has to earn its place.

The code under review is the current checkout (`HEAD`). The PR number is an optional argument; without it, it's derived from the branch.

## Constraints

- **No authentication.** Don't use `gh`, don't read or send `GITHUB_TOKEN`, and don't run git commands that use credentials (e.g. `git fetch origin` over SSH). Use the unauthenticated GitHub API (public repos only, 60 requests/hour — you need at most two) and, if anything must be fetched, anonymous HTTPS (`git -c credential.helper= fetch https://github.com/<owner>/<repo>.git …` with `GIT_TERMINAL_PROMPT=0`).
- **Read-only.** Don't push, commit, comment on the PR, or modify the working tree. The output is the report.

## Step 1 — Identify the PR and the diff

**Running in GitHub Actions** (`GITHUB_EVENT_PATH` is set and its JSON has a `pull_request` object): take everything from there — `pull_request.number`, `title`, `body`, `html_url`, `base.ref`, `base.sha`, `head.sha` — and the repository from `GITHUB_SERVER_URL`/`GITHUB_REPOSITORY`. No API call is needed.

**Running locally:**

1. Repository: parse `<owner>/<repo>` from the URL of the current branch's upstream remote (`git config branch.<branch>.remote`), falling back to `origin` (also when `HEAD` is detached). Both `git@github.com:o/r.git` and `https://github.com/o/r.git` forms occur.
2. PR number: use the argument if given. Otherwise, if on a branch, look it up by branch name: `curl -s "https://api.github.com/repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all"` (for a fork, use the fork owner in `head=`). If that finds nothing or `HEAD` is detached, match the commit instead: `git ls-remote https://github.com/<owner>/<repo>.git 'refs/pull/*/head' | grep $(git rev-parse HEAD)`. If there's still no PR, review the branch against the default branch anyway and say that no PR description was available.
3. PR metadata: `curl -s https://api.github.com/repos/<owner>/<repo>/pulls/<n>` → `title`, `body`, `html_url`, `state`/`merged_at`, `base.ref`, `base.sha`, `head.sha`.

**Then, in both cases:**

- Base: use `base.sha` if it exists locally (`git cat-file -e <sha>`), else `origin/<base.ref>`, else `<base.ref>`. If none is available (e.g. a shallow CI checkout), fetch the base branch anonymously as described above. Compute `MERGE_BASE=$(git merge-base <base> HEAD)`.
- Diff and commits: `git diff --find-renames $MERGE_BASE..HEAD` and `git log --reverse --format='%H%n%B' $MERGE_BASE..HEAD`. Read both in full.
- Compare `HEAD` with the PR's `head.sha`. If they differ (local commits not pushed yet, or the local branch is behind), review `HEAD` and say so at the top of the report.
- If the working tree has uncommitted changes, they're not part of the PR: mention it, and read changed files via `git show HEAD:<path>` where the dirty state would mislead you.
- If the PR is already merged or closed, still review it, but frame findings as follow-ups.

Links in the report point into the PR's "Files changed" view (see Step 5), so the reader lands on the change itself with its diff context. That view shows the PR's current head, so it only matches your line numbers if `HEAD` is the PR head; if it isn't, or there is no PR, use plain `path:line` references instead.

## Step 2 — Build the context that defines "correct"

A diff can only be judged against what it was supposed to do and the rules of the project. Collect these before reviewing:

1. **PR description and commit messages** — the author's stated intent. Note claims you can check ("fixes X", "no behavior change", "adds tests for Y") and anything the change does that isn't mentioned.
2. **Agent/project docs** — if they exist, read `AGENTS.md` and `CLAUDE.md` at the repository root and in every directory on the path to a changed file (nested ones apply to their subtree). Follow links in them to further docs (coding guidelines, testing guidelines, architecture notes) when they're relevant to the kinds of files changed. These are the project's own rules; violations of them are legitimate findings, while personal style preferences are not.
3. **Related epic** — epics are planning documents under `epics/` (see the plan-epic skill: files named `yyyy_mm_dd_<feature>.md` with an "Implementation Phases" section). Look for one that this PR belongs to: a `[Feature N]`-style prefix in the title, an epic file referenced in the description or commits, an epic file touched by the diff, or an epic whose phases clearly describe this change. Check both the base and the head version. If you find one, identify the phase this PR implements and use it as the spec: does the PR do what the phase says, without pulling in work from other phases? Does it contradict an architecture decision in the epic? If no epic matches, skip this — don't force one.
4. **Surrounding code** — for each changed hunk, read enough of the enclosing function/module, its callers and its tests to understand how it is used. Use grep in the repository to find callers of changed signatures and other places that follow the same pattern. If the change depends on interfaces outside the repository (another repo, a published API, a CLI), check them as they were when the PR was written, using anonymous HTTPS fetches only; flag later drift separately rather than blaming the PR for it.

## Step 3 — Review the changes

Focus on what the PR changed. Unchanged code is only in scope when the change breaks it (e.g. a caller of a modified function now gets wrong results) — pre-existing issues the PR merely sits next to don't belong in this review.

Look, roughly in this order of importance, for:

- **Correctness** — logic errors, wrong conditions, off-by-one, unhandled error paths, races, broken edge cases (empty, null, zero, max), behavior that contradicts the description, commits, or epic phase.
- **Security** — injection, missing validation/authorization, secrets, unsafe deserialization, trust of external input. For smart contracts or signing code: replay, reentrancy, access control, integer issues, signature/hash construction.
- **Breakage of other code** — changed signatures/semantics with unupdated callers, migrations, config, persisted formats, public APIs.
- **Tests** — new behavior or a fixed bug without a test that would catch a regression; tests that don't actually assert what they claim.
- **Project rules** — violations of the AGENTS.md/CLAUDE.md guidelines or linked docs, and PR scope rules (e.g. mixing refactors with features when the project forbids that).
- **Maintainability** — only when concrete: duplicated logic that already exists as a helper (name it), dead code introduced by the PR, misleading names or comments.

Don't report things a formatter, linter, type checker or CI would catch, matters of taste, or "consider adding a comment" style suggestions. Don't run the project's build or tests unless it's cheap and would confirm a specific suspicion.

Write each candidate down with: file, line(s) in the PR head, what's wrong, the concrete scenario where it goes wrong, and the fix.

## Step 4 — Verify every finding

Reviews lose credibility through false positives, so re-check every candidate before reporting it. For each one, go back to the code and try to **disprove** it:

- Is the line actually changed by this PR (or directly broken by it)? If not, drop it.
- Re-read the code around it — is the case handled elsewhere (a guard upstream, a type that rules it out, a caller that never passes that value, a test that covers it)?
- Can you state a concrete input or sequence of events that triggers the problem? If you can only say "might be an issue", drop it or, if the potential impact is severe, keep it as a question for the author.
- Is it actionable — is it clear what the author should change?
- Is it a duplicate of another finding? Merge them.

When there are many candidates (roughly more than five) and subagents are available, verify them in parallel: give each verifier the repository path, the file and lines, and the claimed problem, and ask it to independently confirm or refute it with evidence. Give it the claim, not your reasoning, so it isn't anchored on your conclusion.

Keep only findings that survive. It's fine — good, even — to end up with zero findings; say so plainly rather than padding the report.

## Step 5 — Report

Rank the surviving findings by priority:

- **🔴 Blocking** — bugs, security issues, data loss, broken callers, clear contradiction of the stated intent or epic phase. Must be fixed before merging.
- **🟠 Should fix** — missing tests for new behavior, project-guideline violations, edge cases likely to bite.
- **🟡 Consider** — concrete, low-cost improvements worth the author's time. Keep this section short; drop it if empty.

Link every finding to its location in the PR's "Files changed" view: `<PR URL>/files#diff-<file hash>R<start>-R<end>`, where `<file hash>` is the SHA-256 hex digest of the file path in the PR head (`printf '%s' 'path/to/file.ts' | sha256sum`) and `R` refers to line numbers in the new version of the file. Use `L<n>` instead of `R<n>` for a deleted line, which only exists in the old version. These anchors only resolve to lines that appear in the PR diff (changed lines and the few lines of context around them). For anything else, such as a caller in a file the PR didn't touch, link the file at the PR head instead: `https://github.com/<owner>/<repo>/blob/<head sha>/<path>#L<start>-L<end>`. Also give the local `path:line` for quick navigation.

Use this format:

```markdown
# Review: <PR title> (#<n>)

<PR URL>

<One or two sentences: what the PR does and your overall verdict (e.g. "Looks good to merge", "One blocking issue").>
<If an epic was used: "Checked against <epic file>, phase <N>.">
<Any context gaps, e.g. "PR description unavailable (API rate limit).">

## 🔴 Blocking

### 1. <Short title>
[`path/to/file.ts:42-48`](<PR URL>/files#diff-<file hash>R42-R48)

<What is wrong and the concrete scenario where it fails.>

**Suggested fix:** <specific change, with a short code snippet if it helps>

## 🟠 Should fix

### 2. ...

## 🟡 Consider

### 3. ...
```

Number findings continuously across sections so the user can refer to them ("fix 1 and 3"). Omit empty sections.
