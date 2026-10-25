# Payroll release evidence

## Monthly all-department attendance uploads - 25 October 2026

The three report upload buttons now open a whole-month preview without a department or day selector. Files include every department/date in the chosen month and can combine late/early details. The preview supports 15,500 employee/date rows with 100 displayed per page; edits and selections survive paging/search. HR can apply reviewed statuses to selected search matches. Needs review rows still block Save.

The additive monthly RPC groups rows through the existing attendance writer inside one transaction; an error in any later department/date rolls back earlier writes. The dedicated SQL suite validates 1,023-row saving, atomicity, retries, role/company/module/password checks, stale data, payroll locks and completed late reviews. Existing raw-punch and daily department workflows remain available. Install `20261025170000_monthly_attendance_import.sql` before the frontend; the fresh installer includes it.

Validation: 119 unit tests, 22 SQL suites plus repair/fresh/reverse-order checks, Chrome mocked-backend checks covering monthly combined reports, pagination/hidden selections, wrong-month denial and retry, and production build. A 500-person x 31-day CSV was parsed/staged as 15,500 distinct rows locally. Production publication and signed-in company testing are separate verification steps.

## Biometric report imports and attendance review — 25 October 2026

Attendance now accepts the supplied absence, late-coming and early-going CSV formats through the existing department/date editor. Time reports support the optional From Date / To Date heading, blank rows, AM/PM values and seconds. Employee IDs match exact saved biometric IDs; employee names and report shifts are checked against Staff Master. Review and save each department/date separately.

Missing-punch, afternoon-arrival and morning-departure cases start as **Needs review — choose status**. Absence-report rows also require a deliberate status decision because missing punches do not prove absence. HR verifies evidence, corrects supported times/minutes and selects the reviewed status before saving. No punch time or full-day/half-day decision is inferred. Review flags remain unsaved drafts rather than a persistent pending-attendance queue.

Late and early imports preserve the other side's times, minutes and edits staged in the same form. Completed whole late minutes remain subject to the existing monthly review; early-going minutes subtract the staff member's configured daily early grace and remain separate from the 25-minute late allowance. Save uses the existing attendance API and its company/role, stale-data, payroll-lock and completed-review checks. Raw punches remain separate. This frontend release requires no database migration and grants no new company or platform permissions.

| Check | Release evidence |
|---|---|
| Unit tests | 115 passed, including the supplied report formats, missing punches, afternoon arrivals and combined late/early imports |
| SQL regression suites | All 21 passed in isolated PGlite with synthetic fixtures; blank/unknown attendance statuses rejected |
| Installation regressions | Repair preservation, complete fresh install and reverse platform/payment upgrade order passed in isolated PGlite |
| Browser checks | Chrome suite passed for uploads, combined edits, save/retry, unresolved-status denial, fresh early grace, superseded uploads, closed editors, module screens, responsive layouts and role navigation; backend responses were mocked |
| Production build | Passed |
| Live deployment verification | Pending publication and verification against the selected release commit |

No production employee attendance, salary or leave records were changed by these checks. Signed-in live company testing is separate from the mocked-browser and isolated-database evidence. See [department attendance and report uploads](bulk-attendance.md) and [monthly lateness](monthly-lateness.md) for the workflow and limits.

## Frontend refresh — 25 October 2026

The frontend refresh introduces lighter navigation, clearer summary cards, compact pending-work panels, a restyled login and a mobile module selector. The selector uses the same role and company-module filters as desktop navigation. Staff names and headings stay visible inside scrollable staff tables; print output retains the full table.

Validation: 97 unit tests passed. The Chrome suite passed across eight module screens, staff creation and letter forms, 390px and 320px layouts, mobile module selection, staff-table scrolling and restricted staff navigation. Backend responses in this suite are mocked. This update requires no database migration.

## Reliability update — 24 October 2026

The reliability fixes discard stale company responses, clear the previous workspace while loading, require released payroll and hold-aware backend eligibility for bank exports, preserve payment holds through platform upgrades, handle Windows test-file line endings, and select the default month in India time. Missing platform infrastructure now produces a visible warning rather than silently looking like an ordinary permissions result.

| Check | Current evidence |
|---|---|
| Unit tests | 97 passed |
| Baseline SQL scenarios | All 21 passed in isolated PGlite with synthetic fixtures |
| Platform/payment integration and repair | Passed; no platform owner granted automatically |
| Complete fresh install and reverse platform/payment upgrade order | Passed in isolated PGlite |
| Public production login | Rendered in a fresh browser at https://payroll-orpin-one.vercel.app/ |
| Updated browser suite | Passed in installed Chrome: eight modules, staff form, letter merge, mobile layout, staff navigation and paused-company rendering; mocked backend with real API client |
| Live database repair | Applied and verified: release guard and payment/platform gateway present; all 24 existing payroll table counts and business-data hashes unchanged; 246 staff and 248 memberships preserved; zero new platform owners |
| Frontend publication | Verify production app.js against the selected release commit; Vercel Git integration is the publication path |
| Shared leaked-password protection | Still disabled; management credentials unavailable |

The complete fresh installer is `node scripts/database-install.mjs`. Existing databases must use the checked repair path in `operations.md`, not replay the baseline. The repair migration is `supabase/migrations/20261024123135_payroll_reliability.sql` and requires existing system-user and payment-hold tables. Platform ownership remains an explicit separate grant.

Real password/email onboarding, real bank processing, device integration, restore testing, current statutory rate review and production load testing remain outside this verification. Local fixtures do not establish production readiness.

## Historical v0.1 evidence — 13 October 2026

The following records the original build. Its deployment/browser blockers and test counts describe that date, not the current release status above.

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
