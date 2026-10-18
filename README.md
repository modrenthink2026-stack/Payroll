# Payroll Manager — application v0.1

Started: 13 October 2026. Owner account confirmed: modrenthink2026-stack.

Status: application source and isolated Supabase backend implemented. Repository: https://github.com/modrenthink2026-stack/Payroll. Production deployment is blocked by Vercel team permissions. Live biometric sync and statutory filing are not implemented. See `docs/release-status.md` for executed checks and limitations.

Confirmed scope: India payroll; 101–500 staff; individual staff logins; eSSL / ZKTeco attendance; security deposit at 10% of earned gross salary. Exact device model remains unknown. Multi-company support is a proposed default, with strict company separation; confirm company/state list before implementation.

## Contents

- public/: responsive staff/HR/accountant workspace and Supabase password authentication client.
- database/payroll.sql: consolidated schema for a fresh installation; the existing Supabase project is already provisioned. Do not rerun this file there.
- tests/: unit tests, rollback PostgreSQL scenario suites and optional Playwright UI tests.
- scripts/build.mjs and vercel.json: deployment build and security headers.
- docs/operations.md: login, onboarding, configuration and deployment instructions.

- docs/requirements.md: modules, calculation rules, roles, workflows and safeguards.
- docs/software-review.md: current vendor benchmarks, sources and architecture choices.
- docs/backlog.md: ordered build milestones and proposed acceptance tests.
- docs/employee-lifecycle.md: offers, appointments, assessments, increments, confirmation and exit letters with approval/payroll links.
- templates/: blank staff, attendance, leave, assessment, increment and letter-register CSV templates.
- checks/validate_starter.py: document/template completeness and illustration checks only.

This project is separate from the existing construction project. Persistent payroll data uses separate `payroll_*` tables and a private business-logic schema in the authorized existing Supabase project. No construction tables or Auth settings were changed. Do not upload real employee salary, bank, PAN, identity data or passwords into GitHub.

Run `npm ci`, `npm test` and `npm run build`. Deploy `dist` to Vercel using the repository root. No service-role or database secrets belong in the browser. The included Supabase key is a public publishable key; database policies and authenticated RPC permissions enforce access.

The earlier planning documents describe the broader target product. Features still pending are explicitly listed in the release status. Starter checks (`python3 checks/validate_starter.py`) check requirement coverage only and are separate from executed application tests.

Current role access, name-based staff Login IDs and account activation: [Access and logins](docs/access-and-logins.md).
