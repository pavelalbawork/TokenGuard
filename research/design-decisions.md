# Design Decisions — Locked, Candidate, and Open

Status: distilled from design-spec.md + critique pass, 2026-04-05.

---

## Locked (Not Reopening)

- **Platform:** macOS menu bar app via `MenuBarExtra`
- **Framework:** SwiftUI, targeting macOS 14+
- **No Dock icon** — menu bar only
- **Credentials in Keychain** — no plaintext, no UserDefaults
- **Card-based layout** — services as collapsible sections, accounts as cards within
- **Progress bar color semantics:** blue/green (0-75%), orange (75-95%), red (95-100%)
- **System fonts** (SF Pro), semantic colors for automatic dark/light mode
- **Native popover material** — translucent, follows system appearance

## Candidate (Preferred, Need Validation)

### Menu bar icon
- **Preferred:** `chart.bar` (SF Symbol), with badge overlay for warning/critical states
- **Alternative:** Dynamic ring (Apple Watch activity style) showing worst-case account
- **Open question:** Should the icon show the worst status across ALL accounts, or only the "primary" account? Activity ring is elegant but may be too subtle at menu bar size.

### Account card density
- **Preferred:** Compact — account name, single progress bar, fraction text, countdown timer. ~4 lines per account.
- **Alternative:** Rich — add predicted-usage overlay, per-model donut chart, billing cycle timeline
- **Recommendation:** Start compact. Rich variants are additive and can ship later.

### Multi-account credential flow
- **Preferred:** API key input (explicit, reliable, user understands what they're giving)
- **Candidate:** Auto-detect CLI session (read local JSONL/config files from Claude Code, Codex CLI)
- **Candidate:** Browser cookie extraction (fragile, privacy concerns)
- **Recommendation:** V1 = API key only. CLI session detection as V2 convenience.

### Refresh model
- **Preferred:** Timer-based polling, configurable interval (default 5 min), with manual refresh button
- **Open question:** Should each service have its own interval? Antigravity local endpoint is cheap (30s ok), Gemini Cloud Monitoring is expensive and slow.

## Decided (2026-04-05)

### 1. Limits: CLI parsing + manual fallback
- Parse limits from CLI output where available (Claude `/usage`, Codex `/status`)
- Fall back to user-configured limits
- When limit is unknown: show raw usage number, no progress bar, with "Set limit" action
- Progress bar only appears when a limit is known

### 2. Reset model: multi-window
- Support rolling (5h), weekly, monthly, and daily window types
- Each account can have multiple windows (e.g., Claude Pro: 5h rolling + weekly cap)
- Countdown text adapts: "Resets in 2h 15m" (rolling), "Resets Mon" (weekly), "Resets May 1" (monthly)
- Requires `ResetInfo` model replacing the single `resetDate` field

### 3. Gemini: V1 with caveats
- Include Gemini via Cloud Monitoring API (Vertex AI only)
- Clear "requires GCP project + OAuth" messaging in Add Account flow
- AI Studio users shown "not supported yet" with explanation
- OAuth flow with refresh token needed (non-trivial)

## Remaining Open

### 4. Add Account UX per provider
Now that Gemini is in V1 with OAuth, the Add Account flow needs per-provider adaptation:
- Claude/OpenAI: paste API key
- Gemini: OAuth flow (browser redirect → token exchange → store refresh token in Keychain)
- Antigravity: toggle on/off, auto-detect local agent

### 5. Settings scope for V1
- Refresh interval: global or per-service?
- Launch at login: yes
- Notification thresholds: defer to V2?
- Show/hide accounts: yes
