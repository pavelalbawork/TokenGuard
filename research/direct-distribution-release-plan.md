# Direct Distribution Release Plan

Date: 2026-04-08
Target: GitHub + notarized macOS download + optional donation path

## Decision

We are not optimizing for the Mac App Store.

We are optimizing for:

- preserving the app's current value as a local developer utility
- keeping local subscription tracking features intact where practical
- shipping faster with lower product risk
- avoiding App Sandbox-driven rearchitecture that would gut the product

## Release Goal

Ship a stable direct-download macOS menu bar app through GitHub Releases.

Distribution model:

- source on GitHub
- signed + notarized release artifact
- donation link in repo and release notes

## Scope Rules

### Must preserve

- local subscription tracking as the product thesis
- Claude local tracking
- Codex local tracking
- multi-account support where it already works
- menu bar utility workflow

### Must fix before release

- fake or misleading UX
- trust-damaging deletion behavior
- obvious secrets/privacy problems
- missing release packaging basics

### Do not spend time on yet

- Mac App Store compliance
- sandbox rearchitecture
- major visual redesign
- analytics platform integration
- advanced monetization
- donor-only features

## Baseline Checkpoint

This checkpoint exists so feature-preservation work has a regression reference.

### Baseline status on 2026-04-08

- `swift test`: passing
- `xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Release -sdk macosx build`: passing
- repo working tree: clean
- current branch: `main`

### Baseline commands

Run these before major changes and after each packet lands:

```bash
swift test
xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Debug -sdk macosx build
xcodebuild -project UsageTool.xcodeproj -scheme UsageTool -configuration Release -sdk macosx build
```

### Baseline manual feature checklist

These are the behaviors we should manually verify before making structural changes and again before release:

1. App launches as a menu bar extra.
2. Popover opens reliably and does not crash on first run.
3. Existing saved accounts render without corrupting local state.
4. Claude accounts can still read local subscription/session usage.
5. Codex accounts can still read local subscription/session usage.
6. Refresh action updates state without hanging the UI.
7. Settings open and close cleanly.
8. Adding an account does not crash the app.
9. Removing an account does not corrupt remaining accounts.
10. Stale/error states render instead of crashing.

### Baseline evidence to capture

Before large refactors, capture:

- one debug launch screenshot
- one screenshot with at least one Claude account loaded
- one screenshot with at least one Codex account loaded
- a copy of passing test/build output in the PR description or work log

## Fastest Safe Release Path

### Phase 1: Freeze and stabilize current feature set

Goal:

- keep current local subscription-tracking features working
- avoid regressions while we remove obvious launch risks

Tasks:

- define baseline
- avoid changing provider architecture unless required
- keep current local-file approach for direct distribution

### Phase 2: Remove trust-damaging issues

Goal:

- make the app honest enough to release publicly

Tasks:

- remove fake History view
- stop showing false `UNLIMITED` where data is actually unknown
- fix delete behavior or fix delete copy
- remove PII logging
- remove hardcoded secrets from source or cut affected provider from release

### Phase 3: Make release packaging real

Goal:

- produce something that looks like a legitimate product, not a dev build

Tasks:

- add app icon assets
- set version/build numbers
- add signing/notarization flow
- create release artifact workflow

### Phase 4: Public launch surfaces

Goal:

- make GitHub the distribution and trust surface

Tasks:

- README
- install instructions
- limitations/support/privacy notes
- donation link placement

## True Blockers

- hardcoded secret in source
- fake/misleading product surfaces
- no real release packaging
- privacy-hostile logging
- deletion flow that does not do what the product says it does

## Not Blockers

- theme polish
- animation polish
- richer history feature
- perfect accessibility pass
- comprehensive metrics/analytics

## Parallel Packets

## Packet A: Baseline and regression guardrails

Owner: Codex

Scope:

- document baseline
- keep verification commands current
- define what must not regress

Files:

- `research/direct-distribution-release-plan.md`
- optional test/readme updates that clarify verification

## Packet B: Trust cleanup

Owner: Codex

Scope:

- remove PII logging
- fix delete flow or align delete copy
- remove false/misleading UI states

Primary files:

- `UsageTool/Services/UsagePollingEngine.swift`
- `UsageTool/Views/ServiceSectionView.swift`
- `UsageTool/Storage/AccountStore.swift`
- `UsageTool/Storage/UsageSnapshotCache.swift`
- `UsageTool/Storage/KeychainManager.swift`
- `UsageTool/Views/MainPopoverView.swift`

## Packet C: Public-launch UX cleanup

Owner: Gemini CLI

Scope:

- improve first-run clarity
- remove fake History
- remove false `UNLIMITED`
- tighten setup wording for real users

Primary files:

- `UsageTool/Views/MainPopoverView.swift`
- `UsageTool/Views/AddAccountView.swift`
- `UsageTool/Views/SettingsView.swift`

## Packet D: Packaging and distribution

Owner: Codex

Scope:

- version/build numbers
- icon assets
- signing/notarization docs or automation
- GitHub release checklist

Primary files:

- `project.yml`
- `UsageTool/Resources/Assets.xcassets`
- release docs/scripts

## Packet E: GitHub launch surfaces

Owner: Gemini CLI

Scope:

- README
- install instructions
- support/privacy/limitations text
- donation path wording

Primary files:

- `README.md` if added
- `research/` docs as needed

## Recommended Order

1. Packet A
2. Packet B
3. Packet C
4. Packet D
5. Packet E

Packets B and C can run in parallel if the file ownership is split clearly.

## Regression Gate

Do not merge a packet unless:

1. `swift test` passes
2. Debug build passes
3. Release build passes
4. Manual checklist items relevant to the changed surface still work
5. no new misleading copy or fake states were introduced

## GitHub Launch Checklist

### Code

- no hardcoded secrets in shipped source
- no fake History
- no false `UNLIMITED`
- no PII logging
- delete flow is honest

### App artifact

- app icon present
- version/build numbers present
- signed build
- notarized build
- tested install flow

### Repo surfaces

- README with value proposition
- install steps
- known limitations
- support/contact path
- donation link

## Donation Path

Keep it simple:

- GitHub Sponsors if available
- otherwise Stripe payment link / Ko-fi / Buy Me a Coffee

Place it in:

- README
- GitHub Releases notes
- project website if one exists

Do not block features behind donations in v1.
