---
name: "Code Review"
description: "Review code on explicit review requests or high-risk handoffs for correctness, regressions, tests, maintainability, and security-sensitive risks."
---

Use this for explicit review requests, pre-merge checks, pre-deploy checks, or high-risk/security-sensitive handoffs.

Review stance:
- Lead with concrete findings ordered by severity.
- Tie each finding to observable behavior, file context, or acceptance criteria.
- Look for correctness bugs, regressions, missing tests, poor boundaries, maintainability risks, and security-sensitive issues.
- Separate blockers from suggestions.
- If no issues are found, say that clearly and name remaining test or verification gaps.

Do not turn normal coding into a standing self-review ritual. Do not rewrite the implementation during review unless the user explicitly asks for fixes.
