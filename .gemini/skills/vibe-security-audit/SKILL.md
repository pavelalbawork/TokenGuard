---
name: "Vibe Security Audit"
description: "Run a practical 80/20 security audit for AI-generated web apps and automations, with quick-scan, pre-deploy, and full-checklist modes."
---

Use this for security reviews of AI-generated or rapidly built web apps, client apps, automations, and integrations. Trigger when the user asks for a security audit, before public/client deploys, or after changes touching auth, sessions, permissions, PII, secrets, uploads, database writes, RLS, webhooks, payments, paid APIs, external integrations, or credentialed automation.

Do not run this for small UI-only edits, routine prose changes, or local-only scripts with no secrets or external effects.

Modes:

1. quick-scan
- Use during active development or after a focused risky change.
- Check secrets/env leaks, public env prefixes, auth middleware/route protection, server-side validation, client-access database security, paid API rate limits, webhook signature checks when present, and obvious dependency/package risk.
- Output: posture, blockers, quick wins, and checks needing deeper audit.

2. pre-deploy
- Use before client handoff, public demo, production deploy, auth/database/payment launch, or external integration launch.
- Check the full 80/20 surface: secrets/env, gitignore/history, source-map/client bundle risk, auth middleware/default-deny, Supabase/Firebase/RLS/storage policies, service role isolation, server-side schema validation, identity from session, webhooks, uploads, CORS as a browser boundary, rate limits, package audit, lockfile, suspicious dependencies, and error leaks.
- Output: posture, critical/high findings, quick wins, deploy blockers, and verification evidence.

3. full-checklist
- Use only when explicitly requested or when the risk justifies a comprehensive audit.
- Start by reading architecture, entry points, auth/data flow, and deployment config. Expand to full-repo review as needed.
- Give each relevant checklist area a verdict: pass, fail, partial, not applicable, or not verified.

Stack conditionals: apply the database, auth, and storage items only when the project uses those surfaces (e.g., RLS/Supabase/Firebase items do not apply to projects without a client-accessible DB).

See `Toolbox/catalog/references/vibe-security-audit-checklist.md` for the full checklist areas, finding format, and corrections to common bad advice.
