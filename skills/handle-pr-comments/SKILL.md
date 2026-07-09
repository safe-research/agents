---
name: handle-pr-comments
description: Handle unresolved review comments on a GitHub pull request by implementing the requested changes and printing a suggested reply for each thread. Use when the user asks to handle, address, or resolve PR/review comments/feedback, given a PR URL, a PR number, or nothing (current branch).
---

# Handle PR Comments

This skill works through the **unresolved** review comment threads on a GitHub pull request and implements the requested changes. Resolved threads MUST NOT be touched or considered.

It talks to GitHub directly over the REST and GraphQL APIs via `curl`/`jq` — it does NOT depend on the `gh` CLI being installed.

## 0. Authentication

Determining which threads are unresolved ideally uses a *read-only* call to GitHub's GraphQL API (see step 2a) — that API requires an authenticated request for every query, even against public repos, unlike REST v3 which allows some unauthenticated reads. Nothing in this skill ever writes to GitHub (see step 3), so if a token is used it never needs write/`repo` scope — a plain read-only PAT (or a fine-grained token scoped to `Pull requests: Read-only`) is enough.

Try to resolve a token, but don't require one:

1. Use `$GITHUB_TOKEN` or `$GH_TOKEN` from the environment if set.
2. Otherwise, if the `gh` CLI happens to be installed and authenticated, `gh auth token` can populate it — but don't require `gh` for anything beyond this optional convenience.
3. Otherwise, proceed with no token.

If no token was resolved, check repo visibility with an unauthenticated request (this endpoint allows anonymous reads for public repos):

```
curl -s "https://api.github.com/repos/<org>/<repo>" | jq .private
```

- `false` (public) — continue with the token-less fallback in step 2b.
- `true` (private), or the request fails/rate-limits — a token is required to see anything on this repo at all. Ask the user for one and stop until they provide it.

## 1. Resolve the PR reference

Determine the PR in this order:

1. **URL given** — use it directly.
2. **Only a PR number given** — run `git remote -v` to determine the GitHub org/repo from the `origin` remote (works for both `git@github.com:org/repo.git` and `https://github.com/org/repo.git` forms), then build `https://github.com/<org>/<repo>/pull/<number>`.
3. **Neither given** — determine org/repo from `git remote -v` as above, get the current branch (`git branch --show-current`), and list open PRs with:
   ```
   curl -s ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
     "https://api.github.com/repos/<org>/<repo>/pulls?state=open" \
     | jq '[.[] | {number, title, headRefName: .head.ref}]'
   ```
   This is a public REST read — GitHub allows it anonymously for public repos, so only send the header when a token was actually resolved in step 0. Sending an empty `Authorization: Bearer ` header is treated as an invalid credential and gets a 401, which is worse than sending no header at all. Match entries whose `headRefName` equals the current branch. You MUST present the matched PR number(s) and title(s) to the user and ask for confirmation before proceeding — even when exactly one PR matches. If nothing matches, tell the user and stop.

If a username is also given, remember it for step 2 — only unresolved comments authored by that user must be handled.

## 2. Fetch unresolved review threads

Issue-level PR comments have no resolved state and MUST be ignored — only review comment *threads* carry `isResolved`. Use whichever path matches what step 0 resolved.

### 2a. Primary: GraphQL (token available)

`isResolved` is only exposed via GraphQL. Build the request body with `jq -n` to avoid manual JSON escaping, and POST it to the GraphQL endpoint:

```
query=$(cat <<'GRAPHQL'
query($owner:String!, $repo:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first:100) {
            nodes { id author { login } body path line url }
          }
        }
      }
    }
  }
}
GRAPHQL
)

curl -s https://api.github.com/graphql \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "$query" --arg owner "<org>" --arg repo "<repo>" --argjson pr <number> \
        '{query:$q, variables:{owner:$owner, repo:$repo, pr:$pr}}')"
```

Paginate by passing the previous page's `endCursor` as the `$endCursor` variable while `hasNextPage` is true.

### 2b. Fallback: read the public PR page (no token, public repo only)

There is no supported anonymous API for thread resolution status, so fall back to the `WebFetch` tool against the PR's own GitHub page rather than the API — e.g. `https://github.com/<org>/<repo>/pull/<number>/files` (per-file review view) or `https://github.com/<org>/<repo>/pull/<number>` (conversation view). For each review comment, note its file, line, author, and body, and whether GitHub renders it as collapsed with a "This conversation was marked as resolved" marker — treat those as resolved, everything else as unresolved.

Tell the user before relying on this path:
- It's scraping GitHub's web UI, not a documented API — markup can change, and comments loaded lazily via JS while scrolling can be missed silently.
- If it looks like anything might be missing or ambiguous, say so rather than under-reporting comments — don't silently treat "couldn't tell" as "resolved."
- It only works for public repos; if the repo turns out to be private partway through, stop and ask for a token instead.

### Filtering (both paths)

- Drop every thread where it's resolved.
- If a username was provided, further drop threads that contain no comment authored by that user.

## 3. Handle each remaining thread

Process the remaining threads one at a time. This skill never posts back to GitHub (no reply/resolve mutations, no write scope needed) — it only changes local code and reports to the terminal:

1. Read the comment body, `path`, and `line`; open the file for context to understand what's being asked.
2. Implement the requested change.
3. Print to the terminal, per thread: the thread's `url`, a one-line summary of what was changed, and a suggested reply the user can paste on GitHub. Do not call `addPullRequestReviewThreadReply` or `resolveReviewThread` — resolving/replying is left to the user to do manually.

If a comment is unclear or you disagree with the requested change, print that instead of a code change, so the user can decide how to reply.

## 4. Do not run git commands that need authentication

Do not run any git command that requires authentication against a remote or signing key — e.g. `git fetch`, `git pull`, `git push`, or `git commit` (commit signing may require an SSH/GPG key that isn't configured). This environment may have no git/GitHub credentials at all (see step 0), and these commands are also visible to others and hard to reverse. Only edit files on disk; leave committing, pushing, and replying/resolving on GitHub to the user — unless the user has explicitly authorized doing so and confirmed the credentials are in place.
