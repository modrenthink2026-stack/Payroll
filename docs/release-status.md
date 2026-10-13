# v0.1 release evidence — 13 October 2026

## Implemented

- Responsive UI source: overview, staff master, attendance, leave, payroll/payslips, letters/service, assessments/increments, reports and company settings.
- Supabase password sign-in, token refresh, confirmed-email account linking, role assignment and company separation.
- Staff and restricted pay profiles; effective-dated salary versions; reviewed calendar-day proration and monthly accountant tax inputs.
- Reviewed attendance and biometric CSV import with event deduplication; late/early minutes as reports.
- Individual leave requests, atomic reservations, independent approvals/cancellations and balance adjustments.
- Payroll calculation, missing-record/negative-net exceptions, independent review, input fingerprint checks, locking/release, CSV statements and print/save-PDF payslips.
- Deposit collection/refund ledger, caps and repeated-request/payment-reference protection.
- Letter-type master, template draft merging, placeholder/signatory gate, approval/issue/acknowledgment and print/save-PDF.
- Weighted staff assessments, increment recommendation/accountant review/approval, service decisions and Payroll-specific separation access cutoff.

## Executed checks

| Check | Result |
|---|---|
| JavaScript parsing and production static build | Passed |
| Six domain unit tests: CSV, formula injection, escaping, assessments, letter catalog | Passed |
| PostgreSQL main scenario suite | Passed; transaction rolled back |
| PostgreSQL edge-case suite | Passed; transaction rolled back |
| Direct authenticated table RLS / revoked writes | Passed inside transaction-scoped identities |
| Salary arithmetic and separate employer contributions | Passed for explicit reviewed test inputs, not a legal certification |
| Missing attendance, changed-input review and locked recalculation gates | Passed |
| Deposit/refund retries and duplicate refund reference | Passed |
| Letter placeholders and service isolation | Passed |
| Tenant/staff visibility and tax-write denial | Passed |
| Leave overlap/debit/cancellation | Passed |
| February partial joining, mid-month increment, March TDS projection | Passed |
| Duplicate/unknown biometric punch import | Passed |
| 500 staff / 15,500 attendance records monthly payroll | 500 lines and INR 15,000,000 gross reconciled; one measured calculation 1.708 seconds |
| Test cleanup | Zero test accounts and zero staff records remained; one real initial company |
| Supabase security advisor | No payroll table-policy warning; shared leaked-password protection warning remains |
| Browser UI suite / rendered desktop and mobile inspection | Unavailable: Chromium missing and browser download failed; test script included but did not pass |
| Real password/email onboarding flow | Not run; no user password was requested or reset |
| Production deployment and live smoke test | Blocked by Vercel team HTTP 403 |

## Gauntlet improvements

The strongest outcome risk is releasing a payroll app without independent review and verified hosting/login. Hosting/login are still open gates. During implementation, targeted review found and fixed ambiguous account-linking SQL, missing staff/deposit snapshots on payslips, stale increment approvals after payroll lock, repeated refund posting and access retained by separated privileged staff. Relevant database suites were rerun.

The chosen model is an owned static application with transactional Supabase business logic. Compared with a commercial HRMS and a custom portal plus outsourced payroll API, it gives direct control over the requested employee/deposit workflow, at the cost of maintaining statutory correctness and connectors. The vendor review in `software-review.md` is the market benchmark; this version still falls short of those mature products in filing automation, integrations and production evidence.

Decision: BAR NOT REACHED for the requested built-and-deployed outcome. Source and database implementation are complete for the stated v0.1 scope, but deployment access and browser/real-login validation are unresolved. Do not call this production-ready.

## Pending broader-specification features

Live eSSL/ZKTeco sync and offline connector; multi-shift/overnight attendance derivation; automatic overtime amounts, reimbursement/bonus/arrears calculations; fully versioned statutory rule changes within a payroll period; automated tax slabs, EPS/EDLI splitting and government filing formats; automated leave accrual/carry-forward/expiry; bank-file execution and per-staff partial-payment reconciliation; automatic final settlement; candidate acceptance portal, reviewed company-specific legal letter templates, electronic signatures and email delivery; multi-stage self/manager appraisal and budget calibration; scheduled service-status/access changes; account MFA and backup/restore verification.

The earlier requirements are the target backlog. The UI labels and operations notes distinguish these gaps from implemented features.
