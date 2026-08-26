---
name: implement-sentinel-spec
description: Make a sentinel-test-vectors spec pass against a sentinel engine's `just test-integration-sentinel-engine` integration test — by proposing a corrected verdict or by implementing the engine logic for the transaction category it covers. Use when given the path to a spec file (e.g. `~/repositories/sentinel-test-vectors/specs/safenet/announcement_without_relaying.json`) and asked to check, fix, or implement support for it. Do NOT use this to run the full test-vector corpus speculatively, or to edit files in the test-vectors repo directly.
---

# Implement Sentinel Spec

A sentinel engine (see
[`docs/sentinel-engine.md`](https://raw.githubusercontent.com/safe-research/safenet/main/docs/sentinel-engine.md))
is scored against
[`sentinel-test-vectors`](https://raw.githubusercontent.com/safe-research/sentinel-test-vectors/main/README.md)
specs: each spec is a Safe transaction plus the verdict (`secure`/`insecure` + rule citation) a
correct engine must return. This skill takes one failing or new spec and either proposes a corrected
spec or implements the missing engine logic.

**Input:** `spec_path` — full path to the spec file, e.g.
`~/repositories/sentinel-test-vectors/specs/safenet/announcement_without_relaying.json`. Split it
yourself:

- **test-vectors repo root** — everything before `specs/`.
- **spec operand** — everything from `specs/` onward (a leading `specs/` is accepted either way).

If `spec_path` has no `specs/` segment, stop and ask for a corrected path instead of guessing a repo
root.

Run from an engine repository (currently `safenet`) against a `sentinel-test-vectors` checkout.

**Additional context:** free text beyond `spec_path` (special conditions, known constraints,
corrections) is authoritative input to Step 2, not a hint to weigh against your own reasoning. If it
conflicts with what you independently work out, don't silently pick a side — surface the conflict and
ask.

## Step 1 — Run the target spec

Hard prerequisite: the current repo's `Justfile` exposes
`test-integration-sentinel-engine <test-vectors-repo> <spec>` (test-vectors root first, spec operand
forwarded through as the second argument). This is an interface the skill relies on, not something to
rediscover per run — if this repo's recipe doesn't accept a spec operand or doesn't exist, stop and
tell the user rather than improvising a different invocation or editing the recipe yourself.

```sh
just test-integration-sentinel-engine "$test_vectors_repo" "$spec"
```

Read the scorecard — it distinguishes three outcomes that change the diagnosis in Step 2:

- **FAILED** — the engine returned a definite verdict (or, for `insecure`, the right verdict but the
  wrong rule) that disagrees with the spec.
- **SKIPPED** — the engine `abstain`ed where the spec expects a definite verdict; never treat
  `abstain` as an implicit `secure`.
- **Missing** — the spec matched zero specs in the run; a typo in the path fails silently rather than
  erroring, so confirm it resolved.

If the spec already passes, stop — there is nothing to change.

## Step 2 — Diagnose

Read the spec's `transaction`, `verdict`, `rule` (if `insecure`), and `note`. Independent of what the
engine or the spec currently say, work out what the correct verdict actually is:

- Decode `to`/`data`/`operation` against known ABIs; if the transaction batches several calls (e.g. a
  MultiSend-style contract), evaluate each sub-transaction rather than treating the batch as opaque.
- Cross-reference the current repo's `AGENTS.md`/`README` for how rule citations and checks are
  documented, the existing checks for the same transaction category, and the `note` field of
  neighboring specs in the same `specs/<group>/` that already pass. Treat disagreement with these as
  a strong signal, not proof by itself.
- If the correct verdict is genuinely ambiguous, stop and ask — a wrong verdict here is a
  security-relevant mistake, not a cosmetic one.

Write your reasoning out as a short paragraph — what the transaction does, which category/rule
applies, why — before branching. Step 3 hands it to the user as a security-verdict justification;
Step 4 turns it into a permanent code change. Neither should follow from a snap judgment.

Compare your conclusion to the spec and the engine's actual behavior, then pick a branch:

- **The spec's expected verdict/rule is wrong** → Step 3.
- **The engine lacks, or wrongly implements, the logic for this category** → Step 4.

A crashed engine, a timeout, or an unreachable RPC is an infra problem, not a spec or logic bug —
report it as such instead of forcing it into one of the branches above.

## Step 3 — Propose a spec fix, then stop

The spec lives in a separate repository from the engine — don't edit it yourself. Present the
proposed correction and stop:

- the corrected `verdict`;
- the corrected `rule` if `verdict` is `insecure` (required there, pattern `R-<major>.<minor>`;
  forbidden when `verdict` is `secure` — see the
  [spec schema](https://raw.githubusercontent.com/safe-research/sentinel-test-vectors/main/schema.json));
- a `note` summarizing why this verdict is correct.

Let the user apply it in the test-vectors repo, or explicitly ask you to — don't write the file or
run its formatter/validator (`bin/check-specs.sh --fix`) yourself.

## Step 4 — Fix the engine

**Generalize to the transaction's category, not the one vector.** Key the check off a
structural/semantic property — a function selector, operation type, contract role, batch shape —
never off this vector's specific address, amount, or nonce. Smell test: if changing the vector's
`nonce` or transfer amount would break your condition, it's overfit. A fixed allow-list of canonical,
well-known contract addresses is fine — the category genuinely is "one of these contracts."

Where checks live, how they're wired into the engine's decision chain, how rule citations are
declared, and how the RPC provider is meant to be used are repo-specific — consult this repo's
`AGENTS.md` (different engines structure this differently). If those docs don't cover implementing a
new check or RPC chain-safety, say so rather than inventing a convention on the spot — that's a
documentation gap to flag, not paper over.

One check applies regardless of what those docs say: if the fix reads onchain state and the engine
has a single RPC endpoint for a single chain, verify the transaction's `chainId` matches that chain
before trusting any data from it, and abstain rather than mis-verdict on a mismatch — nothing
guarantees this is already validated upstream.

Add tests covering the category (an allowed and a denied case at minimum), not a transcription of
this one vector's fields.

## Step 5 — Verify

- Format, lint, and test per this repo's own guidelines (`AGENTS.md`/`CONTRIBUTING`).
- Re-run Step 1 for the target spec, then the full corpus (or at least its group), to confirm no
  regressions: `just test-integration-sentinel-engine "$test_vectors_repo"`.
- If the user applied the Step 3 spec fix, re-verify only after they confirm it — this skill never
  writes to the test-vectors repo itself.

Do not commit or push in either repo unless the user explicitly asks.
