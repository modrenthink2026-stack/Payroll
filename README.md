# Payroll Manager — application v0.1

Started: 13 October 2026. Owner account confirmed: modrenthink2026-stack.

Status as of 24 October 2026: the public login renders at https://payroll-orpin-one.vercel.app/. The reliability database repair is applied; the frontend changes pass local unit, database and browser checks. Verify deployed assets against the release commit as described in the release evidence. Repository: https://github.com/modrenthink2026-stack/Payroll. Live biometric sync and statutory filing are not implemented. See `docs/release-status.md` for dated evidence and limitations.

Confirmed scope: India payroll; 101–500 staff; individual staff logins; eSSL / ZKTeco attendance; security deposit at 10% of earned gross salary. Exact device model remains unknown. Multi-company support is implemented; company access is checked by the backend.

## Contents

- public/: responsive staff/HR/accountant workspace and Supabase password authentication client.
- scripts/database-install.mjs: emits the complete fresh-install SQL in dependency order. `database/payroll.sql` alone omits later system-user, payment-hold and platform upgrades. Never replay the installer against an existing database.
- tests/: unit tests, rollback PostgreSQL scenario suites and optional Playwright UI tests.
- scripts/build.mjs and vercel.json: deployment build and security headers.
- docs/operations.md: login, onboarding, configuration and deployment instructions.
- [Department attendance and biometric report uploads](docs/bulk-attendance.md): absence/early-going CSV formats, missing-punch review and department/date editing.
- [Monthly lateness](docs/monthly-lateness.md): late-coming CSV format, the 25-minute allowance and authorized LOP/CL review.

- docs/requirements.md: modules, calculation rules, roles, workflows and safeguards.
- docs/software-review.md: current vendor benchmarks, sources and architecture choices.
- docs/backlog.md: ordered build milestones and proposed acceptance tests.
- docs/employee-lifecycle.md: offers, appointments, assessments, increments, confirmation and exit letters with approval/payroll links.
- templates/: blank staff, attendance, leave, assessment, increment and letter-register CSV templates.
- checks/validate_starter.py: document/template completeness and illustration checks only.

This project is separate from the existing construction project. Persistent payroll data uses separate `payroll_*` tables and a private business-logic schema in the authorized existing Supabase project. No construction tables or Auth settings were changed. Do not upload real employee salary, bank, PAN, identity data or passwords into GitHub.

Run `npm ci`, `npm test`, `npm run test:db` and `npm run build`. `npm run test:db` uses only synthetic in-memory PostgreSQL fixtures; `npm run test:ui` is the separate browser suite. Deploy `dist` to Vercel using the repository root. No service-role or database secrets belong in the browser. The included Supabase key is a public publishable key; database policies and authenticated RPC permissions enforce access.

The reliability changes discard stale company responses, require released payroll and payment-hold support for bank exports, preserve hold controls across platform upgrades, and use India time for the default payroll month. Existing installations use `supabase/migrations/20261024123135_payroll_reliability.sql` after confirming its system-user and payment-hold prerequisites; see [operations](docs/operations.md). No platform-owner access is granted automatically.

The earlier planning documents describe the broader target product. Features still pending are explicitly listed in the release status. Starter checks (`python3 checks/validate_starter.py`) check requirement coverage only and are separate from executed application tests.

Current role access, name-based staff Login IDs and account activation: [Access and logins](docs/access-and-logins.md).
