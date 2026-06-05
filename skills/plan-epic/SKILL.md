---
name: plan-epic
description: Create a plan for implementing a larger epics in a project.
---

# Plan Epic

Each larger change to a project, which we refer to as _epic_, MUST be properly planned. For this create an epic specification file in Markdown format under the `epics/` directory from the root of the repository. The specification file MUST have a name that starts with the date (`yyyy_mm_dd`) and include the name of the feature (i.e. `add_feature_template`). It MUST follow the [template epic specification file](./template.md). The plan MUST be proposed as a PR and MUST NOT include any code changes associated with the epic implementation.

Code changes MUST be split into chunks that are easy to review and to understand. For this, it is important that PRs aren't too large, which should be considered when planning the epic. When deciding how to split the implementation into PRs **always optimize for the reviewer**. If refactors are needed, propose them as separate PRs. Phases that can be executed in separate PRs or can be parallized should be explicitly outlined.

Once the feature is complete, the corresponding plan MUST be removed.
