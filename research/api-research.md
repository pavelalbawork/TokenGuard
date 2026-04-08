# TokenGuard API Research Register

> Status: provisional. This file is a research register, not a verified implementation spec.

The previous version mixed correct ideas with unsupported endpoint claims. This replacement keeps only the structure we need for verification and makes uncertainty explicit.

## Verification Standard

Each provider section should only be marked “verified” when it includes:

- official source link
- exact auth method
- exact endpoint or access mechanism
- expected reset / quota semantics
- known limitations

If any of those are missing, the provider stays provisional.

## Current Snapshot

| Provider | Confidence | Current Read |
|---|---|---|
| Anthropic / Claude | Low | Likely has organization/admin usage reporting, but the earlier doc contained incorrect base URLs and should not be trusted as-is. |
| OpenAI / Codex | Medium-Low | Likely has org-level usage/cost surfaces, but exact endpoint set and usefulness for end-user quota display still need verification. |
| Google / Gemini | Low | Probably split between Vertex/GCP metrics and local CLI/session stats. Product fit may be weaker or more indirect than the others. |
| Antigravity | Low | Likely depends on a local agent or local status surface; needs direct verification from the actual tool/runtime. |

## Provider Register

### Anthropic / Claude

- Confidence: Low
- Phase status: Needs re-verification
- What we think may be true:
  - usage/cost reporting is probably organization/admin scoped, not normal end-user API-key scoped
  - local tool surfaces may expose session or subscription information separately
- What must be verified:
  - official docs URL
  - exact base URL
  - exact endpoint paths
  - whether reset timing is directly available
  - whether this is useful for multi-account personal usage tracking
- Current caveat:
  - previous doc used `api.api.anthropic.com`, which is wrong

### OpenAI / Codex

- Confidence: Medium-Low
- Phase status: Needs targeted verification
- What we think may be true:
  - org-level usage and cost reporting likely exists
  - tool-local quota/session surfaces may be distinct from API billing surfaces
- What must be verified:
  - whether the available APIs are suitable for the exact user-facing values we want:
    - usage
    - reset date
    - hard limit
    - cost
  - whether multi-org support is practical
  - whether end-user session limits differ from org-level billing/usage APIs

### Google / Gemini

- Confidence: Low
- Phase status: Needs deeper product-fit evaluation
- What we think may be true:
  - direct end-user “usage dashboard API” may be weak or absent
  - GCP / Vertex metrics may be available but more operational than user-friendly
  - Gemini CLI may expose useful local stats
- What must be verified:
  - whether a menu bar app can reliably obtain actionable quota/reset info
  - whether the support surface is:
    - API
    - Cloud Monitoring
    - CLI parsing
    - or some combination

### Antigravity

- Confidence: Low
- Phase status: Needs direct local verification
- What we think may be true:
  - a local status endpoint or runtime surface may exist
  - there may be a distinction between baseline quota and credit-based usage
- What must be verified:
  - whether the local status mechanism is stable enough for a product dependency
  - whether multiple accounts are a real concept or just multiple sessions/configurations

## Cross-Provider Questions

- Can every provider supply:
  - current usage
  - hard limit
  - reset timestamp
  - plan/tier
- If not, what is the common denominator UI?
- Which providers support true account switching versus only separate credentials or org headers?
- Which providers are suitable for V1 versus better left as later integrations?

## Recommendation

Do not let any implementation lane treat this file as settled API truth yet. The next pass should convert each provider section from “What we think may be true” to “Verified” with official sources.
