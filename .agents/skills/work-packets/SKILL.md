---
name: "Work Packets"
description: "Split a task or substantial plan into bounded packets for multi-tool execution; expand to Prompt Contracts only when delegation-ready handoffs are needed."
---

Use this when the user asks to split work across tools/models, generate packets/prompts, make a plan parallelizable, or prepare work for Claude/Gemini/Antigravity/Codex lanes.

Relationship to policy and Prompt Contracts:
- Routing Check is the lightweight policy reflex: decide single-owner vs fan-out.
- Work Packets designs the split: bounded objectives, owner fit, scope, dependencies, and evidence.
- Prompt Contracts harden handoffs only when packets will be delegated to another tool/model.

Default output:

## Execution Packets

- Packet A: [objective]
  Owner fit: [Codex / Claude / Gemini / Antigravity / etc.]
  Scope: [owned files, surfaces, sources, or decision area]
  Dependencies: [none / waits on X]
  Acceptance evidence: [test, check, artifact, or decision output]

Rules:
- Keep plan synthesis single-owner by default.
- Split research only when there are 2+ independent unknowns whose answers could change the plan.
- For UI-heavy work without settled visual direction, run Design Inspiration Flow before final implementation packets; if packets already exist, use it inside the design packet and return a concrete build packet afterward.
- Keep packet ownership disjoint unless the goal is deliberate comparison or consensus.
- Prefer 2-5 useful packets over exhaustive decomposition.
- Include enough context for copy-paste use, but avoid full Prompt Contract detail unless delegation is imminent.
- If delegation is imminent, expand each packet using the Prompt Contracts skill fields.
