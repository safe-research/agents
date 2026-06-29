## Testing Guidelines

All new code SHOULD include tests in order to increase confidence in its correctness, refactored code SHOULD continue to pass existing tests; modifications MUST be limited to what was intended with the change, and tests SHOULD NOT be modified just to pass. We do not strive for 100% code coverage (with the exception of Solidity code which MUST have 100% coverage) and SHOULD NOT be overly extensive to not cause PR review fatigue (PRs should remain under 300 lines of code including tests).

- Tests SHOULD assert observable behaviour, not implementation details. Prefer testing through stable interfaces, realistic inputs, and meaningful outputs.
- Business logic MUST be tested with behavioural or scenario-style tests. Do not assert on private state, internal helper calls, or incidental call order.
- Mocks SHOULD be limited to true system boundaries such as RPC, network services, chain clients, databases, filesystems, clocks, and external APIs. Internal components SHOULD generally use real implementations.
- Infrastructure code MAY use focused unit tests when implementation mechanics are part of the contract, such as batching, pagination, retry logic, indexing, caching, cryptography, persistence, or RPC usage.
- Edge cases SHOULD be tested at the highest useful level through normal system flow where possible.
- Tests MUST be written in a clear top-down way to facilitate PR review.

Low-signal tests SHOULD be removed or replaced when they are tightly coupled to internals, duplicate higher-level coverage, or create review churn without improving confidence.
