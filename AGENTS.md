# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What This Is

macOS menu bar app (Swift 6.0, macOS 14+) that shows local AI service usage limits and reset timers at a glance. Supports multiple accounts across Claude Code, Codex, Gemini CLI, and Antigravity. Zero third-party dependencies — Apple frameworks only.

## Build & Test

The Xcode project is generated from `project.yml` via XcodeGen — edit `project.yml`, not `.xcodeproj`. After changing `project.yml`, regenerate with `xcodegen generate` (install via `brew install xcodegen` if missing).

SPM is configured as a library target (excludes app entry point and views) so tests can run without Xcode:

```bash
swift build                          # build library target
swift test                           # run all tests
swift test --filter CLIParserTests   # run one test class
```

Full app build requires Xcode:

```bash
xcodebuild build -scheme TokenGuard
xcodebuild test -scheme TokenGuard -destination 'platform=macOS'
```

## Swift 6 Concurrency

This codebase uses Swift 6 strict concurrency. Key patterns to follow:

- All protocols are `: Sendable`
- `UsagePollingEngine` is `@MainActor @Observable` — tests touching it must be `@MainActor`
- Async/await throughout, no completion handlers
- Test mocks use `@unchecked Sendable` and `nonisolated(unsafe)` where needed for static handlers

## Architecture

Polling engine fetches usage from providers on a timer → stores `UsageSnapshot` per account → SwiftUI views observe via `@Observable` and render.

**Providers** each implement `ServiceProvider` protocol (`fetchUsage` + `validateCredentials`). Four providers in `Services/`, one per AI service.

**Account configuration** uses `[String: String]` with keys defined as constants in `Account.ConfigurationKey`. Each provider uses different keys (e.g., `anthropicOrganizationID`, `googleProjectID`, `openAIMonthlyBudgetUSD`). Always use the `ConfigurationKey` constants — never raw strings.

**Multi-window model:** A single account can have multiple `UsageWindow` entries (rolling 5h, weekly, monthly, daily) with independent limits and reset times. This is the core data structure — `UsageSnapshot.windows: [UsageWindow]`.

**CLI Parsers** extract limits from local CLI output (`Codex /usage`, `codex /status`) as best-effort. Falls back to manually configured limits. No progress bar when limit is unknown (by design).

**Storage:** Accounts persist as JSON in `~/Library/Application Support/TokenGuard/`. Credentials in Keychain only, never disk.

**Menu bar icon** color reflects worst usage ratio: gray → orange (≥75%) → red (≥95%).

## Testing Patterns

All external dependencies are protocol-injected. See `Tests/TokenGuardTests/TestSupport.swift` for the full set of mocks:

- **Network:** `URLProtocolMock` + `makeMockedSession()` — set `URLProtocolMock.requestHandler` to stub HTTP responses
- **Keychain:** `InMemoryKeychainBackingStore` — in-memory replacement, thread-safe with `NSLock`
- **CLI:** `MockCLIParser` and `MockCommandRunner`
- **OAuth:** `MockGoogleOAuthManager`

Follow this pattern when adding new providers or testable components: define a protocol, inject it, mock it in tests.

## Adding a New Provider

1. Add a case to `ServiceType` in `Models/Account.swift`
2. Add any provider-specific `ConfigurationKey` constants to `Account.ConfigurationKey`
3. Create a provider struct conforming to `ServiceProvider` in `Services/`
4. Register it in `UsagePollingEngine.init` providers dictionary (`[ServiceType: ServiceProvider]`)
5. Set its polling interval in `serviceRefreshIntervals`
6. Add the UI flow in `Views/AddAccountView.swift` (provider picker, credential fields, validation)
7. Add tests using the protocol-injection pattern from `TestSupport.swift`

## Product Boundaries

Current V1 boundaries:

- Keychain-only credentials, never disk
- No progress bar when limit is unknown
- Menu bar popover as the primary surface
- Multi-window model per account
- Local consumer/provider state first, not a cloud account manager
- Provider parsing is best-effort and may break when upstream local formats change

## Reference

- `README.md` — public product positioning and setup guidance
- `docs/direct-distribution-release.md` — direct GitHub release checklist
- `RELEASE_TEMPLATE.md` — copy/paste release notes template
