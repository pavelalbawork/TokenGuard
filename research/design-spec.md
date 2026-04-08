# TokenGuard Design Exploration

> Status: exploration. This file separates stable design principles from speculative ideas.

The previous version mixed solid menu bar guidance with overly specific UI concepts and implementation assumptions. This version is meant to support decision-making, not pretend the design is already final.

## Design Goal

TokenGuard should feel like a lightweight native macOS utility that answers one question quickly:

> “How close am I to limits or resets across my AI tools and accounts?”

## Stable Principles

- Native macOS menu bar first
- Fast glanceable status from the menu bar icon
- Clear grouping by provider, then account
- Low cognitive load in the default view
- Error and stale states must be obvious
- Multi-account support should feel manageable, not crowded

## Candidate Interaction Model

### Default flow

- menu bar icon shows aggregate state
- click opens a compact popover
- popover groups accounts by provider
- each provider group can expand/collapse
- settings and add-account actions stay easy to reach

This remains the strongest candidate for V1.

## Likely V1 UI Structure

```text
+---------------------------------------+
| TokenGuard                       ⚙     |
+---------------------------------------+
| ▼ Claude                              |
|   Personal Pro                        |
|   [progress] status summary           |
|                                       |
| ▼ OpenAI                              |
|   Work API                            |
|   [progress] status summary           |
|                                       |
| ▶ Gemini                              |
| ▶ Antigravity                         |
+---------------------------------------+
| + Add Account                         |
+---------------------------------------+
```

## Decision Buckets

### Probably locked

- Menu bar icon changes with overall status
- Popover groups by provider
- Expand/collapse is useful for keeping density under control
- Progress plus reset/status text should be the core card content

### Likely but not fully locked

- `DisclosureGroup`-style sections
- one compact account card per account
- settings view for refresh behavior and app preferences
- account add/edit flow separated from the main popover

### Still speculative

- donut charts
- predictive usage overlays
- vertical billing-cycle timelines
- browser-cookie extraction as a first-class auth option
- context-menu action to copy secrets/API keys

Those ideas may be useful later, but they should not be treated as V1 commitments.

## Visual Direction

- Use native macOS semantic colors first
- Prefer quiet surfaces over dashboard-heavy density
- Status colors should do real semantic work:
  - normal
  - warning
  - critical
  - error/stale
- Typography should optimize scan speed, especially for:
  - provider name
  - account label
  - usage fraction
  - reset timing

## Open Design Questions

1. What is the smallest useful menu bar icon language?
   - simple status icon
   - filled status icon
   - ring/progress metaphor

2. How much information belongs in the main popover card?
   - percentage only
   - raw usage and limit
   - reset text
   - stale/auth state

3. How should multi-account scale?
   - flat list under provider
   - pinned primary account + “show more”
   - collapsed secondary accounts by default

4. How should partial provider support be shown?
   Example:
   - “usage available, reset unavailable”
   - “billing available, quota unavailable”

5. Which states deserve dedicated iconography or badges?
   - auth error
   - stale data
   - hard limit hit
   - unknown reset

## Immediate Next Design Work

- decide the minimum viable account card
- decide the menu bar icon state system
- decide how unsupported or partial provider data appears
- sketch one V1 popover and one add-account flow

## Guardrail

Do not turn this document into a component-by-component implementation spec yet. That should happen after provider research and architecture decisions are more trustworthy.
