---
name: "Askaway"
description: "/askaway: Interview the user relentlessly about a plan, design, strategy, architecture, or implementation choice until shared understanding is reached, resolving each branch of the decision tree one by one. Use when the user wants to stress-test a plan, get grilled on a design, choose between meaningful options, or mentions askaway or grill me."
---

Use `/askaway` to interview the user about a plan, design, strategy, architecture, or implementation choice until shared understanding is reached.

This skill is the live-conversation executor for the `clarify-on-low-confidence` and `question-driven-choice-making` policies — invoking it produces the required `Clarify:` options block and the grilling loop those policies demand.

Walk down the decision tree one branch at a time. Resolve upstream dependencies before asking downstream questions.

Ask one question at a time.

For each question:
- explain why it matters;
- provide your recommended answer;
- state what assumption your recommendation depends on.

If a question can be answered by exploring the codebase, project docs, existing files, or generated Toolbox surfaces, inspect those sources instead of asking the user.

Keep going until the important branches are resolved, the user stops the loop, or the remaining uncertainty is low enough to proceed.

Do not use the full loop for trivial edits, obvious bug fixes, reversible micro-decisions, or tasks where the user already gave a complete decision.

When done, summarize:
- agreed decisions;
- unresolved risks;
- assumptions;
- recommended next action.

Related: `strategic-decision-review` (written decision memo after the tree is resolved), `stochastic-consensus` (multi-model independent comparison for high-stakes calls), `offer-and-icp-review` (business-strategy lens for ICP/offer decisions).
