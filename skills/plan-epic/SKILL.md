---
name: plan-epic
description: Always write a plan when developing larger epics: features or refactors that span over multiple pull requests.
---

# Plan Epic

Each larger change to a project, which we refer to as _epic_, MUST be properly planned. For this create an epic specification file in Markdown format under the `epics/` directory from the root of the repository. The specification file MUST have a name that starts with the date (`yyyy_mm_dd`) and include the name of the feature (i.e. `add_feature_template`). It MUST follow the [template epic specification file](./template.md). The plan MUST be proposed as a PR and MUST NOT include any code changes associated with the epic implementation.

Code changes MUST be split into chunks that are easy to review and to understand. For this, PRs MUST have only one main purpose and MUST NOT mix feature work, refactoring, formatting, dependency updates, and unrelated cleanup. PRs SHOULD be below 300 lines of code and change fewer than 10 files. When deciding how to split the implementation into PRs **MUST always optimize for the reviewer**. If refactors are needed, you MUST propose them as separate PRs. Phases that can be executed in separate PRs or can be parallelized SHOULD be explicitly outlined.

Once the feature is complete, the corresponding plan MUST be removed. You MUST append a final phase to the plan to remove the specification file.
