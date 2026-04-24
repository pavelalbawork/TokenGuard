---
name: "Systematic Debugging"
description: "Use for unclear, repeated, or stubborn bugs: reproduce, gather evidence, isolate root cause, fix, and verify before claiming success."
---

Use this when a bug is unclear, repeated, high impact, or the first fix failed.

Workflow:
1. Reproduce or locate the failure evidence before changing code.
2. Map the observed symptom to the smallest likely subsystem.
3. Inspect logs, tests, recent changes, data shape, and configuration before hypothesizing.
4. State the root-cause hypothesis and the evidence for it.
5. Make the smallest fix that addresses the root cause, not just the symptom.
6. Verify with the narrowest reliable check, then broaden if shared behavior might be affected.

Step 6 produces the `Verified: [check] → [result]` artifact required by the `verification-before-completion` policy when the fix qualifies as `@edit`.

Do not guess-and-patch. If reproduction is impossible, say what evidence is missing and choose the safest next diagnostic step.
