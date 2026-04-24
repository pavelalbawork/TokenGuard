---
name: "Refactor Plan"
description: "Plan risky or broad refactors as tiny safe commits with tests, rollback points, and explicit out-of-scope boundaries."
---

Use this when a behavior-preserving refactor is broad, risky, or easy to confuse with feature work.

Plan:
- current pain and desired outcome;
- behavior that must not change;
- smallest safe sequence of commits or packets;
- tests or checks after each step;
- rollback points;
- explicit out-of-scope changes.

Prefer moves that keep the codebase working after every step. Do not use this for small cleanup or feature work disguised as refactoring. Do not mix unrelated cleanup into the refactor.
