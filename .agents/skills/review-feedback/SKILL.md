---
name: "Review Feedback"
description: "Use when receiving concrete change requests from code review or reviewers: verify claims, reject weak suggestions, and apply only technically justified changes."
---

Use this before acting on concrete reviewer or review-thread feedback.

Workflow:
1. Restate each actionable claim.
2. Verify whether the claim is true in the codebase.
3. Classify it as blocker, worthwhile improvement, preference, incorrect, or out of scope.
4. Implement only the changes that are technically justified and within scope.
5. Report what was accepted, rejected, and why.

Do not use this as a generic CI or issue-triage workflow; route failures back to debugging and broader scope decisions back to planning. Do not performatively agree with feedback. If a reviewer is wrong, explain the evidence calmly.
