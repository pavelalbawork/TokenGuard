---
name: "TDD Lite"
description: "Use red-green-refactor when tests-first is appropriate, without forcing strict TDD or deleting exploratory code by default."
---

Use this when the user asks for TDD, when fixing a regression, or when changing a stable public behavior that should be locked down by tests first.

Workflow:
1. Define the behavior externally, from the user's or caller's perspective.
2. Add or update a test that fails for the current behavior.
3. Run the test and confirm the failure is meaningful.
4. Implement the smallest code change to pass.
5. Run the test again, then refactor only if needed.

Do not force strict TDD for throwaway spikes, UI sketching, one-off scripts, or trivial edits. Do not delete exploratory code automatically; if exploration was useful, turn it into a clean implementation with tests.
