# Build sequence and acceptance checks

These are proposed implementation checks, not tests already passed by a working application.

1. Foundation: use the created modrenthink2026-stack/Payroll repository; establish company/state scope; choose stack; account lifecycle and company-scoped permissions; audit, backup and private file storage. Acceptance: staff A cannot query staff B's salary or payslip; HR in company A cannot access company B; reset links reach production and privileged access is audited.
2. Masters: staff import, effective-dated Basic/DA/HRA/other allowance salary versions, departments, shifts, holidays, leave policies and deductions. Acceptance: overlapping salary versions are rejected; missing identifiers are surfaced; historical payslips retain the previous salary version.
3. Leave and attendance: staff applications, manager approval, leave ledger, CSV punch import, reviewed day summaries and late/early reports. Acceptance: simultaneous applications cannot overspend leave; half-day cancellation reverses correct units; weekend policy is visible; night shifts and duplicate imports are handled; missing checkout blocks review rather than creating LOP.
4. Payroll and deposit: monthly earned components, paid/unpaid leave, approved overtime, employee/employer statutory splits, yearly TDS projection interface, 10% earned-gross deposit with approved policy, other deductions and arrears. Acceptance: February/leap year, partial joining/leaving, half-days, changing salary/rates mid-period, negative net and deduction caps are handled; employer contributions never become employee deductions; deposit cap/refund and retry reconcile to ledger.
5. Review, payslips and finance: HR confirmation → accountant review → authorized lock → private payslip release → bank export/payment reconciliation; PF/ESI/TDS statements and journals. Acceptance: changes invalidate approvals; locked batch cannot be overwritten; reports sum to payroll lines; duplicate bank export/retry cannot duplicate a payment; pending/partial/failed payments remain visible; exported statutory file is not labelled filed.
6. Device connector and pilot: obtain exact eSSL/ZKTeco model/firmware/software and sample logs; implement one supported ingestion method, retry/offline queue and sync monitoring. Acceptance: unknown IDs are quarantined, outage recovery is idempotent, timezone matches shift date, no biometric templates are copied, and a full month reconciles with an independent payroll calculation. Measure a 500-staff batch, backup restoration and permissions before release.

## Decisions still needed

Additional milestone: implement the employee lifecycle in `employee-lifecycle.md`. Begin with candidate/offer/appointment and Letter Master after Staff Master; add assessments/confirmation; connect authorized increments to SalaryVersion; connect separation/clearance/final settlement after payroll locking and deposit reconciliation. Verify the ten acceptance cases in that document before release. Company-approved letter formats, signatories, assessment scales/weights, increment budgets, probation periods, notice policies and document-delivery method remain to be configured.

- Company/branch list, states and establishment/employment categories.
- Exact biometric device model, vendor software, protocol/API/SDK and sample export.
- Leave entitlements, holiday calendar, shift grace and late/early policy.
- Deposit eligible staff, aggregate cap, stopping/refund conditions and legal-policy review.
- Opening leave/deposit/loan balances; financial/tax-year payroll and tax history.
- Authorized payroll approver; bank export format; accountant's statutory rule set and filing responsibility.
- Budget and ownership for ongoing compliance updates; hosting and authentication stack.
