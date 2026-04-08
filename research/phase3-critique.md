# Phase 3 Critique — Current Status

Reviewed: 2026-04-05 after a fresh code pass and remediation of the remaining live row/account-save defects.

## Verdict

The app is materially healthier than the earlier critique suggested. Several items that were previously recorded as open are already fixed in code, and the two remaining save-flow defects have now been addressed in this pass. The main risk has shifted from core implementation gaps to a smaller set of workflow and UX holes.

## Fixed Since The Earlier Critique

- `AddAccountView` is now reachable from the menu bar shell instead of being stranded as an unused view.
- `TokenGuardApp` no longer double-initializes store dependencies. The app state is created once in `init`.
- Menu bar status icon is dynamic and reflects worst observed quota ratio.
- Poll cadence is based on enabled account service types, not the global minimum across all possible providers.
- `AccountCardView` shows last-updated age text and marks stale snapshots distinctly.
- Gemini OAuth is using `ASWebAuthenticationSession`; the old note about a missing redirect listener is stale.
- Usage rows now support provider-aware limit saving, derive the visible limit from live account config, and surface save failures instead of swallowing them.
- `AccountStore` mutations are now transactional: failed writes do not leave in-memory state lying about what was persisted.
- Gemini add-account rollback now deletes the just-written Keychain secret if account persistence fails.

## Still Open

### 1. Limit editing is only implemented for supported provider-backed windows
This is the correct behavior for now, but it leaves unsupported rows with no follow-up affordance. Antigravity windows with unknown limits, for example, no longer show a dead "Set limit" action, but they also have no alternative explanatory UI.

### 2. Verification is still constrained by environment
The package test/build path is still sensitive to the local Swift/Xcode setup. The code is structured for testability, but local verification depends on running with a full Xcode toolchain and writable SwiftPM caches.

## Recommended Next Fix Order

1. Decide whether unsupported rows should show explanatory copy instead of just hiding limit editing.
2. Normalize local verification so `swift test` and package inspection run cleanly in the active environment.
