# Provider Research — Verified & Critiqued

Status: critique pass by Claude Code (Opus 4.6), 2026-04-05.
Cross-referenced against api-research.md, Codex's provider implementations, and known API documentation.

---

## 1. Anthropic / Claude

### Verified
- **Endpoint:** `GET https://api.anthropic.com/v1/organizations/{org_id}/usage_report/messages`
  - Note: api-research.md had a typo (`api.api.anthropic.com`). Codex's code uses the correct URL.
- **Auth:** Admin API key (`sk-ant-admin-*`) via `x-api-key` header + `anthropic-version: 2023-06-01`
- **Fields confirmed:** `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, `model`, `service_tier`
- **Grouping:** bucket by day (`bucket_width: 1d`), filterable by model/workspace/api_key
- **Multi-account:** One admin key per org. Multiple orgs = multiple keys.

### Unverified / Problematic
- **Hard limits not exposed via API.** The usage API reports consumption, not your plan's limit. Codex's implementation falls back to `account.configurationDouble(for: .usageLimit)` — meaning the user must manually enter their limit. This is a significant UX gap.
- **Reset semantics are wrong.** Consumer/Pro plans use rolling 5-hour windows + weekly caps, NOT monthly billing cycles. The code assumes a monthly reset via `resetDayOfMonth`. This needs to model rolling windows instead.
- **Personal accounts** may need conversion to Organization to get admin keys. Research says "may" — this needs verification. If personal accounts can't get admin keys, a large segment of users is blocked.
- **Cost API** (`/v1/organizations/{org_id}/cost`) exists but wasn't implemented. Could provide USD cost data as an alternative metric.

### Confidence: MEDIUM
The API exists and the basic parsing is correct, but the limit/reset model is wrong for the most common user plans.

---

## 2. OpenAI / Codex

### Verified
- **Endpoints:** `GET /v1/organization/usage/completions` (usage) and `GET /v1/organization/costs` (billing)
- **Auth:** Bearer token + `OpenAI-Organization` header for multi-org
- **Fields confirmed:** `input_tokens`, `output_tokens`, `model`/`snapshot_id`, `amount_value` (USD cost)
- **Multi-account:** Switch `OpenAI-Organization` header per org — clean multi-account support
- **Budget mode:** Codex correctly implemented dual-path: if `openAIMonthlyBudgetUSD` is configured, report in dollars; otherwise report in tokens

### Unverified / Problematic
- **Requires Owner/Billing role** — not just any API key. Users with "Member" role may get 403s on `/v1/organization/*` endpoints.
- **Hard limits not exposed** — same issue as Anthropic. Monthly budget and token limits are user-configured, not fetched from OpenAI.
- **Codex CLI** has `/status` showing 5-hour and weekly rolling limits — but these are for the Codex product, not the API. The distinction between API usage and product usage needs to be clear.
- **Data delay:** 5-60 minutes. The app should display last-fetch timestamp prominently.

### Confidence: MEDIUM-HIGH
The API is well-documented and the implementation is solid. Main gap is limits not being auto-detected.

---

## 3. Google Gemini

### Verified
- **Mechanism:** Cloud Monitoring API `projects.timeSeries.list` — this is correct for Vertex AI
- **Auth:** OAuth 2.0 access token with `Monitoring Viewer` role
- **Metrics:** `prediction/online/request_count` and `prediction/online/total_tokens` are real Vertex AI metrics

### Unverified / Problematic
- **AI Studio ≠ Vertex AI.** Most individual users use AI Studio (free tier or paid), NOT Vertex AI. AI Studio has NO programmatic usage API — only a web dashboard. This means the Gemini provider only works for GCP/Vertex users, which is a small subset.
- **OAuth flow complexity.** The implementation takes an access token string, but getting one requires an OAuth flow (gcloud auth, service account, or OAuth consent screen). A menu bar app would need to either:
  - Run `gcloud auth print-access-token` periodically (brittle)
  - Implement a full OAuth2 flow with refresh tokens (complex)
  - Accept a service account JSON key (enterprise-only)
- **Quota limits** are per-project and vary by tier. Cloud Monitoring reports current usage but not the limit itself.
- **Gemini CLI `/stats`** — research mentions this but the implementation doesn't use it. Could be a simpler path for users who have Gemini CLI installed.

### Confidence: LOW
The Vertex AI path works but serves a narrow audience. AI Studio users (the majority) are blocked. OAuth complexity is high for a menu bar utility.

---

## 4. Antigravity

### Verified
- **Endpoint:** `GET http://localhost:42424/status` — this is the documented local agent endpoint
- **Auth:** None for localhost (default config)
- **Fields in response (per research):** `quota_percentage`, `reset_timestamp`, `prompt_credits_remaining`, `model_quotas`

### Unverified / Problematic
- **Agent must be running.** If the Antigravity background agent isn't active, the endpoint returns nothing. The app needs to handle this gracefully (not just a network error — a specific "Antigravity agent not running" state).
- **Response schema stability.** Antigravity is in public preview. The `/status` endpoint schema could change without notice.
- **`prompt_credits_total`** — research mentions it but it's unclear if this is always present. Codex's implementation has fallback math to derive it from `remaining` and `percentage`, which is good defensive coding.
- **Baseline vs Credits pools.** Research flags this but neither the research doc nor the code distinguishes between them. Need to understand if `/status` reports them separately.

### Confidence: MEDIUM
The local approach is elegant and simple, but depends on agent availability and schema stability.

---

## Cross-Cutting Issues

### 1. Limits Are Not Auto-Detected (All Providers)
None of the four providers expose "your plan's hard limit" through their APIs. The current code requires users to manually configure limits. This is the single biggest UX problem — a "usage tool" that can't tell you your limit isn't much of a usage tool.

**Options to explore:**
- Scrape/parse CLI output (`claude /usage`, `codex /status`) for limit data — these DO show limits
- Store known plan tiers and their limits as a lookup table (fragile but functional)
- Let users manually set limits and show "X of Y (user-configured)" — honest but less magical

### 2. Reset Windows Are Not Monthly (Claude, Codex)
Consumer plans use rolling 5-hour windows with weekly caps. The code assumes monthly resets. This is fundamentally wrong for the target user and needs to be re-architected.

### 3. Two File Trees Exist
There are duplicate structures at `/TokenGuard/Models/` (root) and `/TokenGuard/TokenGuard/Models/` (Xcode project). Needs consolidation.

### 4. Package.swift vs Xcode Project
Package.swift defines a library target with app code excluded. This should ultimately be a proper Xcode project with an app target. The SPM approach works for backend-only testing but won't produce a runnable .app.

---

## V1 Provider Readiness

| Provider | API Available | Limit Auto-Detect | Reset Accurate | Multi-Account | V1 Ready? |
|----------|--------------|-------------------|----------------|---------------|-----------|
| Claude | Yes (admin key) | No | No (assumes monthly) | Yes | Needs work |
| OpenAI | Yes (owner key) | No | No (assumes monthly) | Yes | Needs work |
| Gemini | Partial (Vertex only) | No | Roughly (daily) | Yes (multi-project) | Not ready |
| Antigravity | Yes (local) | Partial (% based) | Yes (from response) | Untested | Needs verification |

**Recommendation:** V1 should focus on Claude + OpenAI + Antigravity. Gemini should be deferred unless we find a path for AI Studio users.
