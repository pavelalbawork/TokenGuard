# UsageTool — Implementation Brief (v2)

> Native SwiftUI Mac menu bar app showing usage, limits, and reset timing for AI subscriptions with multi-account support.

## Decisions This Brief Is Built On

All decisions below are locked and documented in `research/design-decisions.md`.

- **Limits:** CLI parsing + manual fallback. No progress bar when limit is unknown.
- **Reset model:** Multi-window (rolling 5h, weekly, monthly, daily). Accounts can have multiple windows.
- **Providers:** Claude, OpenAI, Gemini (Vertex AI only, with OAuth caveats), Antigravity.
- **Credentials:** Keychain only. API keys for Claude/OpenAI, OAuth refresh tokens for Gemini, no auth for Antigravity.

## Lane Assignments

| Lane | Host | Scope |
|------|------|-------|
| Backend | Codex | Data models, providers, Keychain, polling, CLI parsers, Xcode project setup |
| Frontend | Antigravity | SwiftUI views, menu bar integration, popover, Add Account flow, Settings |
| Critique | Claude Code | Post-implementation review |

---

## Data Models

### Account
Existing `Account.swift` is salvageable. Keep `configuration: [String: String]` dictionary approach with `ConfigurationKey` constants.

### UsageSnapshot — Needs Rework
Replace single `resetDate: Date` with multi-window model:

```swift
enum WindowType: String, Codable, Sendable {
    case rolling5h      // Claude/Codex consumer plans
    case weekly         // Claude/Codex weekly caps
    case monthly        // API billing cycles
    case daily          // Gemini/Vertex daily quotas
}

struct UsageWindow: Codable, Hashable, Sendable {
    let windowType: WindowType
    let used: Double
    let limit: Double?       // nil = unknown, show "Set limit"
    let unit: UsageUnit
    let resetDate: Date?     // nil for rolling windows where reset is continuous
    let label: String?       // e.g. "5h window", "Weekly cap", "Monthly budget"
}

struct UsageSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let accountId: UUID
    let timestamp: Date
    let windows: [UsageWindow]     // replaces single used/limit/resetDate
    let tier: String?
    let breakdown: [UsageBreakdown]?
    let isStale: Bool              // true when last fetch failed, showing cached data
}
```

`UsageWindow` is the core display unit. Each account card shows one or more windows.

### Display Logic
- `limit != nil` → show progress bar + fraction text + countdown
- `limit == nil` → show raw usage number + "Set limit" action, no progress bar
- `isStale == true` → dim card, show "Last updated X ago"

---

## Provider Implementations

### Common Changes
- All providers return `[UsageWindow]` instead of a single used/limit/reset tuple
- Each provider determines window types from the account's plan/config

### AnthropicProvider
- **Endpoint:** `GET https://api.anthropic.com/v1/organizations/{org_id}/usage_report/messages`
- **Auth:** `x-api-key: sk-ant-admin-*` + `anthropic-version: 2023-06-01`
- **Windows to return:**
  - If consumer plan: rolling 5h window + weekly cap (limits from CLI parsing or manual config)
  - If API plan: monthly billing window (limit from manual config or cost endpoint)
- **New:** Add CLI parser for `claude /usage` output to extract current limits and window status
- **Existing code:** `AnthropicProvider.swift` — parsing logic is sound, needs window model refactor

### OpenAIProvider
- **Endpoint:** `GET /v1/organization/usage/completions` + `/v1/organization/costs`
- **Auth:** `Bearer sk-*` + `OpenAI-Organization: org-*`
- **Windows to return:**
  - If consumer plan: rolling 5h window + weekly cap (limits from CLI parsing or manual config)
  - If API plan: monthly budget window (limit from manual config)
- **New:** Add CLI parser for `codex /status` output to extract limits
- **Existing code:** `OpenAIProvider.swift` — dual-path (token vs dollar) logic is good, needs window refactor

### GeminiProvider
- **Endpoint:** Cloud Monitoring API `projects.timeSeries.list`
- **Auth:** OAuth 2.0 access token (needs refresh token flow)
- **Windows to return:**
  - Daily window: RPD quota (limit from Cloud Monitoring quota endpoint or manual)
  - Token window: TPM quota if available
- **New:** Implement OAuth2 flow:
  1. Open browser → Google consent screen
  2. Receive auth code via localhost redirect
  3. Exchange for access + refresh tokens
  4. Store refresh token in Keychain
  5. Auto-refresh access token before each request
- **Existing code:** `GeminiProvider.swift` — monitoring API parsing is correct, needs OAuth layer
- **Add Account UX:** Show "Requires Google Cloud project" + "Sign in with Google" button

### AntigravityProvider
- **Endpoint:** `GET http://localhost:42424/status`
- **Auth:** None
- **Windows to return:**
  - Primary window from `quota_percentage` + `reset_timestamp`
  - Per-model windows from `model_quotas` breakdown
- **New:** Detect "agent not running" (connection refused) as distinct from server error
- **Existing code:** `AntigravityProvider.swift` — largely correct, good fallback math

### CLI Parsers (New)
```swift
protocol CLIParser {
    func parseUsageOutput() async throws -> [UsageWindow]
}
```
- `ClaudeCodeCLIParser` — run `claude /usage` (or read JSONL logs), extract window status + limits
- `CodexCLIParser` — run `codex /status`, extract window status + limits
- These are best-effort. If CLI isn't installed or output format changes, fall back to manual limits.

---

## UI Components

### Menu bar icon
- SF Symbol `chart.bar`, with color/badge reflecting worst status across enabled accounts
- States: normal (monochrome), warning (orange badge), critical (red badge)

### Main popover
```
+---------------------------------------+
| UsageTool                    ↻   ⚙️   |
+---------------------------------------+
| ▼ CLAUDE                              |
|   Personal Pro                        |
|   5h: [████████░░░░] 75% • 2h 15m    |
|   Wk: [██░░░░░░░░░░] 30% • Mon       |
|                                       |
|   Work (API)                          |
|   Mo: [████░░░░░░░░] 20%             |
|   $10.50 / $50.00 • May 1            |
|                                       |
| ▼ CODEX                               |
|   Default                             |
|   5h: [████████████] 100% ⚠️ • 10m   |
|   Wk: [██████░░░░░░] 55% • Mon       |
|                                       |
| ▶ GEMINI (collapsed)                  |
| ▶ ANTIGRAVITY (collapsed)             |
+---------------------------------------+
| + Add Account                         |
+---------------------------------------+
```

### Account card anatomy
Each card shows N `UsageWindow` rows:
- Window label prefix (5h/Wk/Mo/Da)
- Progress bar (only if limit known) with color coding
- Percentage (only if limit known) OR raw number
- Countdown text

### Add Account — per-provider flows
- **Claude / OpenAI:** Provider picker → name → paste API key → optional org ID → test → save
- **Gemini:** Provider picker → name → "Sign in with Google" → OAuth browser redirect → auto-save tokens
- **Antigravity:** Provider picker → name → test localhost connection → save (no credentials needed)

---

## Project Structure

Consolidate into single Xcode project. Remove root-level duplicate files.

```
UsageTool/
├── UsageTool.xcodeproj/
├── UsageTool/
│   ├── UsageToolApp.swift
│   ├── Models/
│   │   ├── Account.swift           # Keep existing
│   │   ├── UsageSnapshot.swift     # Rework: UsageWindow model
│   │   └── UsageStatus.swift       # Keep existing
│   ├── Services/
│   │   ├── ServiceProvider.swift   # Update protocol for [UsageWindow]
│   │   ├── AnthropicProvider.swift # Refactor for multi-window
│   │   ├── OpenAIProvider.swift    # Refactor for multi-window
│   │   ├── GeminiProvider.swift    # Add OAuth layer
│   │   ├── AntigravityProvider.swift # Add agent-not-running state
│   │   ├── UsagePollingEngine.swift
│   │   └── CLIParsers/
│   │       ├── CLIParser.swift
│   │       ├── ClaudeCodeCLIParser.swift
│   │       └── CodexCLIParser.swift
│   ├── Auth/
│   │   └── GoogleOAuthManager.swift  # New: OAuth2 flow for Gemini
│   ├── Storage/
│   │   ├── KeychainManager.swift
│   │   └── AccountStore.swift
│   ├── Views/
│   │   ├── MainPopoverView.swift
│   │   ├── ServiceSectionView.swift
│   │   ├── AccountCardView.swift
│   │   ├── UsageWindowRow.swift      # New: single window row
│   │   ├── UsageProgressBar.swift
│   │   ├── CountdownTimerText.swift
│   │   ├── AddAccountView.swift
│   │   └── SettingsView.swift
│   └── Resources/
│       └── Assets.xcassets
└── Tests/
    └── UsageToolTests/
        ├── ProviderTests.swift     # Update fixtures for multi-window
        ├── CLIParserTests.swift    # New
        ├── KeychainManagerTests.swift
        └── TestSupport.swift
```

---

## Implementation Order

### Phase 1: Backend (Codex)
1. Create Xcode project, consolidate file trees
2. Rework `UsageSnapshot` → `UsageWindow` model
3. Update `ServiceProvider` protocol to return `[UsageWindow]`
4. Refactor all 4 providers for multi-window returns
5. Implement `ClaudeCodeCLIParser` and `CodexCLIParser`
6. Implement `GoogleOAuthManager` (browser redirect → token exchange → Keychain storage)
7. Update `UsagePollingEngine` for per-service intervals
8. Update tests

### Phase 2: Frontend (Antigravity)
1. `UsageToolApp` with `MenuBarExtra` and dynamic status icon
2. `MainPopoverView` with manual refresh button
3. `AccountCardView` showing multiple `UsageWindowRow`s per account
4. `UsageWindowRow` — progress bar (if limit known) OR raw number + "Set limit"
5. `AddAccountView` with per-provider auth flows (key paste, OAuth button, auto-detect)
6. `SettingsView` — global refresh interval, launch at login
7. Wire to `AccountStore` + `UsagePollingEngine`

### Phase 3: Critique (Claude Code)
1. Security: credential handling, OAuth token storage, no plaintext leaks
2. Edge cases: offline, stale data, auth expiry, agent not running, concurrent refreshes
3. UX: accessibility, VoiceOver labels, keyboard navigation
4. Performance: memory usage, polling efficiency, wake-from-sleep behavior

---

## Verification

- [ ] Can add accounts for all 4 services with their respective auth flows
- [ ] Credentials stored in Keychain exclusively
- [ ] Multi-window display works: 5h + weekly for Claude/Codex, monthly for API, daily for Gemini
- [ ] Progress bar only shows when limit is known
- [ ] "Set limit" action works when limit is unknown
- [ ] CLI parsing extracts limits from Claude /usage and Codex /status
- [ ] Gemini OAuth flow completes: browser → consent → tokens → stored → refresh works
- [ ] Antigravity shows specific "agent not running" message when local agent is down
- [ ] Countdown timers tick correctly for all window types
- [ ] Menu bar icon reflects worst-case status
- [ ] Stale data shown with "Last updated X ago" after network failure
- [ ] Dark and light mode correct
- [ ] App launches at login when configured
