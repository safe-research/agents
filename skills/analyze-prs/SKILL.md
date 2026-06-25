---
name: analyze-prs
description: Generate a pull request analytics report for a repository (author, time to close, comment counts). Only invoke via the explicit `/analyze-prs` slash command — never for responding to or acting on individual PR comments.
---

# Analyze PRs

Produce a structured PR analysis report for a repository, covering author, time to close, and comment count per PR, with optional diff size and per-user comment breakdown. Unless the user specifies a different timeframe, default to the last 30 days.

All data is fetched from the GitHub REST API via `curl` — no `gh` CLI required.

## Authentication tiers

| Tier      | Token required    | Extra calls per PR | Data available                                                   |
|-----------|-------------------|--------------------|------------------------------------------------------------------|
| **Basic** | No (public repos) | 1                  | Author, time to close, accurate total comment count              |
| **Full**  | Yes (recommended) | 4                  | + diff size (additions/deletions), comments broken down per user |

For private repos, a token is always required. Stop and ask the user if none is provided.

**Providing a token:**
```bash
export GITHUB_TOKEN=<personal-access-token>
# Classic token: needs `repo` read scope
# Fine-grained token: needs "Pull requests" read permission
```

Set up auth args once and reuse across all calls:
```bash
if [[ -n "$GITHUB_TOKEN" ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
else
  AUTH_ARGS=()  # unauthenticated — public repos only, 60 req/hour
fi
ACCEPT=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
API="https://api.github.com"
```

---

## Step 1 — Determine scope

- **Repository**: infer `owner/repo` from the git remote, or ask the user:
  ```bash
  git remote get-url origin
  # parse OWNER and REPO from the URL
  ```
- **Timeframe**: compute `since_epoch` from the user's expression, defaulting to 30 days before today:
  ```bash
  # last N days/weeks/months (Linux)
  since_epoch=$(date -u -d "N days ago"   +%s)
  since_epoch=$(date -u -d "N weeks ago"  +%s)
  since_epoch=$(date -u -d "N months ago" +%s)
  # macOS: date -u -v-Nd +%s  /  -v-Nw  /  -v-Nm
  ```

---

## Step 2 — Fetch PR list

Use `GET /repos/{owner}/{repo}/pulls` sorted by `created desc`. Paginate and stop as soon as a page contains a PR older than `since_epoch` — no search API needed.

```bash
prs=()
page=1
per_page=100
STATE="closed"  # or "all" to include open PRs

while true; do
  response=$(curl -sf "${AUTH_ARGS[@]}" "${ACCEPT[@]}" \
    "$API/repos/$OWNER/$REPO/pulls?state=$STATE&per_page=$per_page&page=$page&sort=created&direction=desc")

  count=$(echo "$response" | jq 'length')
  [[ "$count" -eq 0 ]] && break

  stop_paging=false
  while IFS= read -r item; do
    item_created=$(echo "$item" | jq -r '.created_at')
    item_epoch=$(date -u -d "$item_created" +%s 2>/dev/null \
              || date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$item_created" +%s)
    if [[ "$item_epoch" -ge "$since_epoch" ]]; then
      prs+=("$item")
    else
      stop_paging=true
    fi
  done < <(echo "$response" | jq -c '.[]')

  $stop_paging && break
  [[ "$count" -lt "$per_page" ]] && break
  page=$(( page + 1 ))
done
```

This avoids the search API entirely, which has a stricter separate rate limit (10 req/min unauthenticated vs. 60 req/hour core).

---

## Step 3 — Fetch per-PR details

For each PR, fetch `GET /pulls/{number}` to get accurate comment counts (and diffs for the full tier). The list endpoint omits `review_comments`, so `comments` alone would silently miss all inline review comments.

```bash
for pr in "${prs[@]}"; do
  number=$(echo "$pr" | jq -r '.number')

  detail=$(curl -sf "${AUTH_ARGS[@]}" "${ACCEPT[@]}" \
    "$API/repos/$OWNER/$REPO/pulls/$number")

  comments=$(echo "$detail"        | jq -r '.comments // 0')
  review_comments=$(echo "$detail" | jq -r '.review_comments // 0')
  total_comments=$(( comments + review_comments ))

  # Full tier only:
  additions=$(echo "$detail" | jq -r '.additions // 0')
  deletions=$(echo "$detail" | jq -r '.deletions // 0')
done
```

Run calls in parallel (`&` + `wait`) to reduce wall-clock time. For unauthenticated access the limit is 60 req/hour — a token raises this to 5000/hour and is strongly recommended for repos with more than ~50 PRs.

---

## Step 4 — Full tier only: comments per user

Only run this step if a token is available.

```bash
# Inline review comments
curl -sf "${AUTH_ARGS[@]}" "${ACCEPT[@]}" \
  "$API/repos/$OWNER/$REPO/pulls/$number/comments?per_page=100"

# Issue-level (top-level) comments
curl -sf "${AUTH_ARGS[@]}" "${ACCEPT[@]}" \
  "$API/repos/$OWNER/$REPO/issues/$number/comments?per_page=100"

# Formal reviews (approve / request-changes / comment)
curl -sf "${AUTH_ARGS[@]}" "${ACCEPT[@]}" \
  "$API/repos/$OWNER/$REPO/pulls/$number/reviews?per_page=100"
```

Merge all three; count by `.user.login`, excluding the PR author's own comments. Paginate each endpoint when the result length equals `per_page`.

---

## Step 5 — Compute durations

Use `created_at` as the start time and `closed_at` (falling back to now for open PRs) as the end time:

```bash
created_epoch=$(date -u -d "$created" +%s 2>/dev/null \
             || date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$created" +%s)

if [[ -n "$closed" ]]; then
  end_epoch=$(date -u -d "$closed" +%s 2>/dev/null \
           || date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$closed" +%s)
else
  end_epoch=$(date -u +%s)  # still open
fi

diff_secs=$(( end_epoch - created_epoch ))
diff_days=$(( diff_secs / 86400 ))
diff_hours=$(( (diff_secs % 86400) / 3600 ))
```

> **Note:** `created_at` is used as the ready-to-review time rather than the `ready_for_review` timeline event (which requires an extra API call per PR). For PRs that started as drafts this slightly overstates the review period.

---

## Output format

### Per-PR table

Columns (exactly, in this order): `PR#`, `Author`, `Title` (truncated to 55 chars), `Duration`, `Comments`.  
Sort by `Comments` descending. Do not include opened date, closed date, or state.

Use fixed-width columns: `PR#` 6, `Author` 12, `Title` 56, `Duration` 10, `Comments` 8.  
Print a `---…` separator line at full width above and below the data rows.

```
PR#    Author       Title                                                    Duration   Comments
-----------------------------------------------------------------------------------------------
#469   nlordell     Add State Machine Implementation                         1d 4h      27
#468   remedcu      Epoch Rollover Library                                   2h         19
...
-----------------------------------------------------------------------------------------------
```

**Full tier** — append two extra columns after `Duration`, before `Comments`:

```
… Duration   Additions  Deletions  Top Commenters                           Comments
```

List up to 3 top commenters as `name (N)`, sorted by count descending, in a single cell.

### Summary section

Print immediately after the closing separator, no blank line between:

```
Summary (N PRs):
  Authors        : alice (5), bob (3), …   [sorted by PR count descending]
  Avg comments   : N
  Total comments : N
  [Full tier] Largest PR   : #N <title> — +A / -D
  [Full tier] Top reviewer : <name> (N comments across M PRs)
```

## Notes

- If rate limited (HTTP 403/429), inspect `X-RateLimit-Reset` (Unix timestamp) to know when to retry.
- Paginate detail endpoints (`/comments`, `/reviews`) when result length equals `per_page`.
- A token is strongly recommended for any repo with more than ~50 PRs in the timeframe.
