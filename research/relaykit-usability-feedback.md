# RelayKit Usability Feedback — Current Status

Reviewed: 2026-04-05 after the UsageTool follow-up fixes landed.

This file is now split into fixed-vs-open so it stops acting like stale backlog input for future orchestration passes.

## Fixed / No Longer Representative Of Current Product State

- The product-side items previously inferred from this session that were already fixed in `UsageTool` should not be treated as open backlog anymore:
  - dynamic menu bar icon
  - smarter polling cadence
  - stale snapshot age text
  - `ASWebAuthenticationSession` support
  - working "Set limit" flow
- The earlier write-failure blind spot is now addressed: limit saves surface persistence errors, and the store no longer mutates in-memory state before a successful write.
- The Gemini add-account path now cleans up Keychain state if account persistence fails.

## Still Open In RelayKit

### 1. `confirm_task(accept=false, change=...)` does not materially regenerate task parts
The tool claims the recommendation changed, but the generated task parts can remain identical. That makes change requests untrustworthy as a control-plane action.

### 2. Archetype classification still appears overly noun-driven
Tasks that are obviously research-oriented can still be pushed into build-oriented archetypes when the prompt mentions a concrete stack like SwiftUI or menu bar apps.

### 3. Reflections still do not appear to influence future recommendations
The recorded reflection signal exists, but similar follow-up tasks can still receive the same mismatched defaults. This is still the most important live learning-loop gap.

### 4. Discoverability is still weaker than it should be
RelayKit remains easier to miss than it should be because the trigger language is more product-descriptive than user-language descriptive. The earlier recommendations about explicit "parallelize / use all my tools / distribute work" phrasing still stand.

### 5. MCP output UX still needs a human-summary layer
Raw JSON is usable for tooling but too blunt as a direct operator surface. A concise top-level summary/display field would materially improve task intake and checkpoint readability.

## Recommended Next RelayKit Work

1. Make change requests actually regenerate recommendations or fail loudly.
2. Add research-first archetypes or improve verb-sensitive task classification.
3. Feed reflection outcomes back into recommendation defaults.
4. Tighten instruction and skill trigger language around user phrasing for multi-tool distribution.
