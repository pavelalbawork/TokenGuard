---
name: "Context Capture"
description: "Propose, save, or review durable workspace context without turning it into junk memory. Skip: transient troubleshooting notes, per-task scratch, NOW-style operational status, or one-off observations (those belong in chat or NOW.md, not context)."
---

Use this when Pavel asks to save/update/capture context, when durable context appears, or when reviewing context candidates.

Do not use for transient troubleshooting notes, per-task scratch, NOW-style operational status, or one-off observations — those belong in chat or `NOW.md`, not in the context reservoir.

Modes:

1. propose candidate
- Default mode when durable context appears but Pavel has not explicitly asked to save it.
- Write or present a candidate with target file, scope, proposed entry, reason it is durable, source, and review date.
- Do not write permanent context without explicit approval.

2. save context
- Use when Pavel explicitly says save, update, add, or capture this.
- Write to the smallest correct target: project CONTEXT.md, stream CONTEXT.md, or one file under Context/.
- Keep entries short, dated when useful, and easy to skim.

3. review candidates
- Read Context/CANDIDATES.md.
- For each open candidate, recommend accept, revise, reject, defer, promote to learned rule, or promote to NOW.
- Merge accepted candidates into target files only with approval or explicit instruction.
- After review, record the outcome in Context/CANDIDATES.md: move the entry under `Reviewed Candidates` with outcome + date, or delete it once the target file reflects the merge.
- If promoted to a learned rule, hand off to the LEARNED_RULES.md flow — do not write the rule from this skill.

Candidate format:

## Candidate: [short title]

Target: `[path]`
Scope: global / stream / project
Proposed entry:
- ...
Why durable:
- ...
Source:
- chat / file / decision / research result
Status: proposed
Review by: YYYY-MM-DD

Keep context distinct from learned rules and NOW:
- Learned rules are behavioral corrections for agents.
- Context is durable background, preferences, decisions, and source pools.
- NOW is current operational state.
