# Architecture Critique — Exploratory Code Review

Status: Claude Code critique of Codex/Antigravity exploratory output, 2026-04-05.
These files are not approved for production but contain useful patterns worth preserving.

---

## What Codex Got Right

### Protocol design (`ServiceProvider.swift`)
- `ServiceProvider` protocol with `fetchUsage` + `validateCredentials` is clean and extensible
- `NetworkSession` protocol for dependency injection — makes every provider testable with mock HTTP
- `ProviderSupport` utility namespace with typed JSON helpers — avoids `as?` chains in providers
- Proper `Sendable` conformance throughout for Swift 6 concurrency

### Account model (`Account.swift`)
- `configuration: [String: String]` dictionary is pragmatic — avoids a rigid schema when each provider needs different config keys
- `ConfigurationKey` constants prevent string typos
- Helper methods (`configurationDouble`, `configurationInt`) reduce boilerplate in providers

### Test structure (`ProviderTests.swift`)
- `URLProtocolMock` pattern is correct for mocking HTTP without third-party deps
- Each provider has at least one test with realistic JSON payloads
- Tests verify both parsing logic and URL construction

## What Needs Fixing

### 1. Reset model is fundamentally wrong
**Impact: HIGH**

All providers assume monthly reset dates via `ProviderSupport.monthlyResetDate()`. But:
- Claude Pro/Max: 5-hour rolling window + weekly cap
- Codex: 5-hour rolling window + weekly cap
- Antigravity: 5-hour or variable windows depending on plan

The `UsageSnapshot.resetDate` field needs to become richer:
```
// Instead of a single resetDate:
struct ResetInfo {
    let windowType: WindowType  // .rolling(hours: 5), .weekly, .monthly, .daily
    let windowResetDate: Date?  // next reset for rolling/weekly
    let billingCycleDate: Date? // monthly billing cycle if applicable
}
```

### 2. Limits are user-configured, not fetched
**Impact: HIGH**

No provider API returns "your plan allows X." The code silently falls back to `max(totalUsed, 1)` when no limit is configured, which makes the progress bar show 100% always. This is misleading.

**Recommendation:** Make the limit explicitly optional. If unknown, show usage as an absolute number without a progress bar, and offer "Set your limit" in the UI.

### 3. Gemini OAuth is unimplemented
**Impact: MEDIUM (if Gemini ships in V1)**

`GeminiProvider` takes an access token string but doesn't handle token refresh. OAuth access tokens expire in ~1 hour. A menu bar app polling every 5 minutes would need:
- A refresh token stored in Keychain
- Token refresh logic before each request
- Re-auth flow when refresh token expires

This is a significant chunk of work that isn't reflected in the current code or tests.

### 4. Two file trees
**Impact: LOW (cleanup)**

Root-level `Models/`, `Views/`, `Services/` AND `TokenGuard/TokenGuard/Models/`, etc. Need to pick one.
- The `TokenGuard/TokenGuard/` tree is the more complete one (has all providers, tests)
- Root-level tree appears to be Antigravity's output
- Consolidate into a single Xcode project structure

### 5. Package.swift defines a library, not an app
**Impact: MEDIUM**

The Package.swift produces a library target and excludes app code. This works for running tests via `swift test` but won't produce a `.app` bundle. For the actual app, we need either:
- An Xcode project (`.xcodeproj`) with an app target
- Or SwiftPM executable target with proper entitlements

The library approach is fine for the backend/service layer during development. The app target can wrap it later.

### 6. `JSONSerialization` instead of `Codable`
**Impact: LOW**

Providers use `JSONSerialization.jsonObject()` → `[String: Any]` → manual extraction. This works and the `ProviderSupport` helpers make it clean enough, but:
- No compile-time type safety on response shapes
- Easy to miss a field or typo a key
- `Codable` structs would catch mismatches earlier

**Recommendation:** Keep the current approach for V1 (it handles API response variations well). Consider `Codable` response types when provider APIs stabilize.

---

## Architecture Decisions To Lock

### Persistence
- **Accounts list:** JSON file in Application Support (`~/Library/Application Support/TokenGuard/accounts.json`)
- **Credentials:** macOS Keychain (already implemented correctly in `KeychainManager`)
- **Usage cache:** In-memory only (not persisted). Last snapshot per account survives the polling cycle but not app restarts. Can add persistence later if needed.

### Polling
- Global timer, configurable interval (default 5 min)
- Per-service minimum interval enforcement (Antigravity: 30s, others: 60s)
- Manual refresh via button
- Show "Last updated: X ago" per account to communicate freshness

### Error states
- Network failure: show last-known data with "stale" badge + timestamp
- Auth failure: inline error on account card, "Re-enter credentials" action
- Service down: grey out card, show "Unavailable" text
- Agent not running (Antigravity): specific message "Start Antigravity agent to see usage"

### App target
- Xcode project with macOS app target (not SwiftPM executable)
- `MenuBarExtra` with `isInserted` binding
- SPM package for the service layer (testable independently)
- Minimum deployment: macOS 14

---

## Salvageable Code

These files from the exploratory phase are architecturally sound and can survive into implementation with targeted fixes:

| File | Status | Required Changes |
|------|--------|-----------------|
| `ServiceProvider.swift` | Good | Keep as-is |
| `Account.swift` | Good | Keep as-is |
| `UsageSnapshot.swift` | Needs change | Add optional limit, add ResetInfo |
| `AnthropicProvider.swift` | Needs change | Fix reset model (rolling windows) |
| `OpenAIProvider.swift` | Good | Fix reset model |
| `AntigravityProvider.swift` | Good | Add "agent not running" error state |
| `GeminiProvider.swift` | Needs decision | Keep if Gemini in V1, else defer |
| `ProviderTests.swift` | Good | Update test fixtures for new reset model |
| `KeychainManager.swift` | Not reviewed | Needs audit |
| Views/* | Not reviewed | Antigravity output, needs integration |
