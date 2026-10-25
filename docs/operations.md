# Application operations

## Current environment

Application: `modrenthink2026-stack/Payroll`, repository root. Build: `npm ci && npm test && npm run build`; deployment output: `dist`. This is a static frontend backed by authenticated Supabase RPCs. It has no third-party production package dependency.

Supabase project: `uvowltyjnzqtozygalhf`. The read-only inspection on 24 October found 20 exposed payroll tables, all with RLS enabled. Direct client writes are revoked; business operations go through `payroll_api` to checked private functions. Private request records deduplicate retries. No service-role key is present in source. Platform-administration RPCs were initially absent and were installed by the reliability repair later that day, with no platform owner granted automatically.

The confirmed existing owner account is assigned Payroll administrator access to the initial `My Company` record. Sign in using its existing password; no password was reset or new password generated. Existing construction data, user accounts, email settings and redirect URLs remain unchanged.

## First use

Password recovery is available from the login screen. See `password-recovery.md` for the email-link, paste-link and shared-account behavior.

1. Administrator edits company name/address, workweek, holidays, signatory and reviewed statutory settings.
2. HR adds staff, component salary, joining date and biometric ID; annual leave opening balances are defaults to review, not statutory entitlements. HR posts dated leave adjustments with reasons for accrual/carry-forward/expiry.
3. HR activates staff logins from Staff Master and shares the generated username privately. Staff must change their temporary password before opening the workspace. Existing confirmed email accounts retain the supported email-linking path. No caller may pick an administrator role during registration.
4. Administrator assigns an independently authorized accountant to a confirmed account. Manager role is assigned first, then linked by manager email in the reporting staff’s master. Only assigned teams are visible to a manager; salary profiles remain restricted.
5. Accountant enters reviewed annual tax liability and tax already paid, PT and other monthly deductions per staff. This is an annual-projection input workflow, not an automatic slab tax engine.
6. HR records reviewed attendance and approves staff leave requests. Missing attendance blocks payroll approval and does not automatically create LOP. Imported punches never directly deduct salary.
7. Accountant/admin calculates a selected month. HR confirms inputs; a different authorized accountant reviews; administrator authorizes/locks and releases payslips. Changes to input data invalidate pending approval. Locked runs cannot be recalculated or silently corrected.
8. Statements export as CSV. The reliability fix requires a released payroll run before preparing bank payments and obtains unpaid, unheld rows from the backend; missing hold support blocks the export. Bank payment/refund references record reconciled payments; the app does not execute transfers. Same refund reference and duplicate request ID cannot post twice.

## Hosting and release verification

The public login rendered at `https://payroll-orpin-one.vercel.app/` in a fresh browser on 24 October. This checks rendering, not real password sign-in or parity with the current local commit. The original 13 October project-creation HTTP 403 is historical; the current connector also denied deployment-list access, and the CLI had no saved credentials. Do not infer the latest fixes are live from login availability.

Use the existing Payroll project under team `team_GhYmkNGIfZQmNTBoU6183VFh` and repository `modrenthink2026-stack/Payroll`; framework Other, build command `npm run build`, output `dist`, root repository directory. Verify the intended commit, database migration and production alias before marking a release complete. `vercel.json` configures security headers. Do not deploy into the construction project's root or domains.

Verify that the exact Payroll origin is in Supabase's authorized email redirect allowlist without replacing the construction Site URL. Verify password recovery and real staff/password sign-in on the deployed site. The shared email service may impose rate limits; configure an appropriate SMTP service before onboarding hundreds of users. No emails were sent during the reliability checks.

## Fresh installation / schema history

For a **fresh compatible Supabase database only**, run `node scripts/database-install.mjs` and save its output as UTF-8 SQL for execution in an authorized administrative session. It concatenates, in order:

1. `database/payroll.sql` — consolidated baseline, including earlier historical upgrades.
2. `database/system-users-upgrade.sql`.
3. `database/salary-payment-holds-upgrade.sql`.
4. `database/platform-admin-upgrade.sql`.

Do not replay older upgrades already included in the baseline. The installer creates tables and is not an existing-database upgrade command.

For an **existing installation**, inspect installed objects and migration history first. The repair migration is `supabase/migrations/20261024123135_payroll_reliability.sql`; it requires the system-user and payment-hold tables and fails early when they are absent. Apply a missing prerequisite only after checking it is not already installed: those table-creating scripts must not be replayed. The repair replaces affected functions and adds platform structures without recreating employee tables or granting platform-owner access. Keep the browser release paired with the tested backend repair. This migration has passed isolated checks; live application is not yet verified.

For a fresh installation, provision your chosen confirmed owner explicitly after creating the schema. In an authorized administrative SQL session, insert a company and insert the selected confirmed Auth user into `payroll_members` with role `admin`; insert that company's leave policy masters. Platform ownership is a separate explicit grant described in `platform-admin.md`. Do not use automatic first-user-admin registration.

Run `npm run test:db` for the 21 baseline SQL scenario suites, platform/payment integration, complete fresh install, repair and reverse-upgrade-order checks in an isolated PGlite database. Fixtures are synthetic; no live connection is used. These checks test business logic/RLS, not actual Supabase password sign-in. Never convert test identities into real user provisioning.

## Operational limits

Statutory rates must be verified by the accountant before activation. Current modeled wage basis is max(earned Basic+DA, half earned gross), with the configured PF cap; ESI coverage is explicitly reviewed at staff level. Alternative wage treatments and split-period changes need a reviewed extension before payroll use. Employer PF export is a total, not an EPS/EDLI/ECR calculation.

The security deposit policy starts disabled. Enable it only after a lawful policy reference, eligibility and aggregate cap are configured. The app deducts 10% of earned gross, capped by remaining collection balance, and blocks payroll beyond its conservative reviewed-wage deduction limit.

Before production staff onboarding, finish browser validation, enable appropriate password security/MFA requirements, configure email callbacks, confirm retention/backup policy, and perform a restore drill. The shared Supabase security advisor reports leaked-password protection disabled. The connected tools do not expose that Auth setting, and no authenticated management session was available; it remains unresolved. Review the change for both Payroll and Project Manager before enabling it. See [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Running the regression checks

Run `npm ci`, `npm test`, `npm run test:db` and `npm run build`. SQL checks use synthetic, in-memory PGlite databases and never connect to production. For browser checks, install Chromium with `npx playwright install chromium`, then run `npm run test:ui`. On Windows with Chrome installed, use `$env:PAYROLL_BROWSER_CHANNEL='chrome'; npm run test:ui`. Browser requests use the real API client with a mocked backend; screenshots go to ignored `qa/`. These are separate from real-account production checks.


## Monthly attendance upload upgrade

Deploy `supabase/migrations/20261025170000_monthly_attendance_import.sql` before publishing the monthly-upload frontend. It adds `payroll_private.monthly_attendance(jsonb)` and `payroll_monthly_attendance(jsonb)` without changing employee records or existing function definitions. It requires the existing `bulk_attendance` writer and `platform_direct_guard` module guard from the reliability installation. Fresh installs include the equivalent `database/monthly-attendance-upgrade.sql` after platform setup. The frontend fails closed when the endpoint is unavailable; do not substitute sequential browser saves, which could leave a partly imported month. Validate with `npm test`, `npm run test:db`, the Chrome UI suite and `npm run build`. The monthly SQL suite saves 1,023 synthetic rows and verifies rollback across later department failures, stale snapshots, roles, company isolation, paused modules, payroll locks and retries.
