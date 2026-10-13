# Application operations

## Current environment

Application: `modrenthink2026-stack/Payroll`, repository root. Build: `npm ci && npm test && npm run build`; deployment output: `dist`. This is a static frontend backed by authenticated Supabase RPCs. It has no third-party production package dependency.

Supabase project: `uvowltyjnzqtozygalhf`. Payroll has 17 separate exposed tables, all with RLS enabled and authenticated read policies. Direct client writes are revoked; business operations go through `payroll_api` to checked private functions. Private request records deduplicate retries. No service-role key is present in source.

The confirmed existing owner account is assigned Payroll administrator access to the initial `My Company` record. Sign in using its existing password; no password was reset or new password generated. Existing construction data, user accounts, email settings and redirect URLs remain unchanged.

## First use

1. Administrator edits company name/address, workweek, holidays, signatory and reviewed statutory settings.
2. HR adds staff, component salary, joining date and biometric ID; annual leave opening balances are defaults to review, not statutory entitlements. HR posts dated leave adjustments with reasons for accrual/carry-forward/expiry.
3. Staff create accounts with the same email as Staff Master and confirm their email. Existing confirmed Supabase accounts can sign in directly. Verified email linking gives own-staff access. No caller may pick an administrator role during registration.
4. Administrator assigns an independently authorized accountant to a confirmed account. Manager role is assigned first, then linked by manager email in the reporting staff’s master. Only assigned teams are visible to a manager; salary profiles remain restricted.
5. Accountant enters reviewed annual tax liability and tax already paid, PT and other monthly deductions per staff. This is an annual-projection input workflow, not an automatic slab tax engine.
6. HR records reviewed attendance and approves staff leave requests. Missing attendance blocks payroll approval and does not automatically create LOP. Imported punches never directly deduct salary.
7. Accountant/admin calculates a selected month. HR confirms inputs; a different authorized accountant reviews; administrator authorizes/locks and releases payslips. Changes to input data invalidate pending approval. Locked runs cannot be recalculated or silently corrected.
8. Statements export as CSV. Bank payment/refund references record reconciled payments; the app does not execute transfers. Same refund reference and duplicate request ID cannot post twice.

## Vercel deployment blocker

The connected Vercel account can list the existing project-manager project, but creating the Payroll project under team `chandu-7362` (`team_GhYmkNGIfZQmNTBoU6183VFh`) returned HTTP 403, saying the connection is not authorized for that scope. No deployment succeeded and there is no verified live Payroll URL. No authenticated CLI fallback is installed in the workspace.

Restore a connection with project creation/deployment access to that exact team. Import `modrenthink2026-stack/Payroll`, framework Other, build command `npm run build`, output `dist`, root repository directory. `vercel.json` configures security headers. Do not deploy this app into the construction project's root or domains.

After obtaining the final Payroll origin, add that exact origin to Supabase's authorized email redirect allowlist without replacing the construction Site URL. Verify signup confirmation/password recovery and real staff/password sign-in on the deployed site. The shared email service may impose rate limits; configure an appropriate SMTP service before onboarding hundreds of users. No emails were sent as part of this build.

## Fresh installation / schema history

The live schema was installed and refined through five named migrations. `database/payroll.sql` is consolidated fresh-install source; run it only against a fresh compatible database, never replay it against the current project. Supabase manages migration history for the live environment.

For a fresh installation, provision your chosen confirmed owner explicitly after creating the schema. In an authorized administrative SQL session, insert a company and insert the selected confirmed Auth user into `payroll_members` with role `admin`; insert that company's leave policy masters. Do not use automatic first-user-admin registration.

`tests/database.sql` and `tests/edge-cases.sql` contain transaction-scoped scenario checks with test identities and records; all are rolled back. They test business logic/RLS, not actual password sign-in. Run only in an authorized test environment/session. Never convert test identities into real user provisioning.

## Operational limits

Statutory rates must be verified by the accountant before activation. Current modeled wage basis is max(earned Basic+DA, half earned gross), with the configured PF cap; ESI coverage is explicitly reviewed at staff level. Alternative wage treatments and split-period changes need a reviewed extension before payroll use. Employer PF export is a total, not an EPS/EDLI/ECR calculation.

The security deposit policy starts disabled. Enable it only after a lawful policy reference, eligibility and aggregate cap are configured. The app deducts 10% of earned gross, capped by remaining collection balance, and blocks payroll beyond its conservative reviewed-wage deduction limit.

Before production staff onboarding, finish browser validation, enable appropriate password security/MFA requirements, configure email callbacks, confirm retention/backup policy, and perform a restore drill. The shared Supabase security advisor reports leaked-password protection disabled: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
