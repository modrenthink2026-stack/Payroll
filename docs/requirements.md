# Product requirements

Employee lifecycle extension: see `employee-lifecycle.md` for offer/appointment letters, assessments, increment recommendations, service confirmation, termination/relieving/experience letters and related employment documents. Approved lifecycle events drive effective-dated payroll/access changes; document creation alone does not.

## Staff Master

Company, branch, department, employee code, name, employment category, designation, manager, joining/leaving dates, location/state, contact details and employment status. Restricted payroll fields: bank details, PAN, UAN, ESI number, tax declarations and prior-employer tax details. Salary versions contain effective-from/to dates, Basic, DA, HRA, other allowances, monthly gross, employer costs and the component-specific proration/tax/statutory treatment. Blank values are incomplete, not zero. Monthly salary and CTC are distinct.

Bulk import: validate employee codes within company, date ranges, numeric amounts and missing fields; preview rejected rows before committing. No production personal data belongs in source control.

## Roles and individual login

| Role | Allowed work |
|---|---|
| Staff | Own profile, attendance, leave balances/application/status, released payslips and deposit balance; no access to other staff salaries |
| Manager | Assigned-team leave and attendance correction approvals; salary access absent unless separately granted |
| HR | Staff master, shift/holiday/leave masters, attendance review, payroll input preparation |
| Accountant | Payroll calculation/review, statutory reconciliation, bank files, journals and reports |
| Administrator | Company configuration and account/role management; grants are recorded |

Every request and file download requires server-side company and employee authorization. Managers cannot approve their own requests; payroll preparer cannot finalize their own batch. Temporary staff access ends at employment termination according to retention policy. Login requires genuine authentication, password reset, correct production callback URLs, and privileged-account MFA; no demo password is a production credential.

## Attendance and biometric integration

Support shift masters, weekly offs, holidays, grace time, late-coming minutes, early-going minutes, worked hours, overtime approvals, half-days, absent days and regularisation. Night shifts belong to the shift-start work date in Asia/Kolkata. Keep raw punches separate from reviewed daily attendance.

eSSL / ZKTeco is the confirmed device family, not verified compatibility. Capture model, firmware, vendor software, protocol, network and export sample before selecting API/push/SDK connector. Begin with CSV import; use an outbound local connector if devices sit on the office LAN. Do not expose the device directly on the public internet. Collect employee punch ID and event timestamps; fingerprint/face templates remain on vendor equipment.

Deduplicate using company + device + event ID; if IDs are absent, use documented exact-log identity without collapsing different real punches. Quarantine unknown employee IDs, timezone problems, invalid timestamps and ambiguous in/out sequences. Show last successful sync, pending events and failures. Retried imports are idempotent.

Missing punch creates a review item, never immediate loss of pay. Late-coming and early-going are initially reports; any penalty conversion needs an applicable approved policy. Attendance absence, unpaid leave and time penalties cannot deduct the same time twice.

## Leave Master and calculation

Configure CL, SL, earned leave and unpaid leave; add other statutory leave types as applicable. Rules include eligibility, annual/monthly entitlement, accrual, probation, joining/leaving proration, half-days, holiday/weekend treatment, carry-forward cap, expiry, encashment and approval chain. Entitlements are company/state/employment-policy specific, not universal constants.

Balance = opening + credited accrual + adjustments − approved leave consumed − expired balance − encashed balance. Show pending reserved leave separately. Use dated ledger entries for every movement. Reserve units atomically to prevent overlapping or concurrent applications spending the same balance.

States: Draft → Submitted → Approved / Rejected / Withdrawn. Approved leave cancellation requires approval and a reversing ledger entry. Requests overlapping holidays, night shifts or another request follow the configured rule and show charged units before submission. Changes after payroll closure produce an approved adjustment in a later batch, preserving the original payroll.

## Monthly salaries and deductions

Earned gross = earned Basic + DA + HRA + other earned allowances + approved overtime/bonus/arrears/encashment. Each component has a documented proration rule. Reimbursements are separately identified. Calendar-day, fixed-day or working-day denominator is configured and recorded; paid leave counts as paid time. Joining/leaving dates bound eligible time. No unexplained double loss-of-pay deduction.

Net pay = earned gross + payable reimbursements − employee PF − employee ESI − salary TDS − applicable PT/LWF − approved security deposit − other authorized deductions. Employer PF/EPS/EDLI/ESI and administrative costs remain employer costs, not employee deductions. Store money in decimal or integer paise with explicit per-component rounding.

PF and ESI require effective-dated coverage, membership history, wage-basis definition, rates, caps and rounding. Do not equate every statutory basis with gross or Basic alone. Salary TDS uses the applicable tax-year regime, annual taxable-income projection, declarations, prior employment and year-to-date deductions; it is not a flat 10%. Statutory exports and tax form labels are versioned for the applicable reporting period. Accountant must verify active official rules before a production run.

Payroll states: Draft → Calculated → HR Inputs Confirmed → Accountant Reviewed → Authorized → Locked → Payment Pending → Partially Paid / Paid / Failed. Any pre-lock input change invalidates review. Lock snapshots attendance, salary and rule versions. Post-lock corrections use linked adjustment batches, never overwrite released payslips. Payment retries cannot duplicate bank instructions; paid status requires reconciled payment evidence, not file export.

## Security Deposit — confirmed basis

Configured target deduction: 10% of earned gross salary. Exclude reimbursements and employer contributions from this base. Applies only to eligible staff under an approved lawful policy; eligibility, lifetime cap, stop condition and refund timing remain unresolved. Inactive until that policy is verified, with written authorization recorded where required. Staff consent alone must not be treated as proof that the deduction is legally permitted.

Deposit is a refundable employee liability with per-staff ledger: opening + deductions − refunds ± approved adjustments = closing. Enforce policy cap, applicable wage-deduction limits and nonnegative net-pay controls; show blocked amounts for review rather than silently deducting. Salary TDS remains separate. Refunds, forfeiture and final settlement require an auditable decision and applicable legal basis. Payroll batch posting to the ledger is idempotent.

Illustration only, not statutory calculation: earned gross INR 30,000; configured deposit at 10% = INR 3,000. Assuming independently approved employee statutory/other deductions of INR 2,500 and no reimbursements, net pay = INR 24,500. Deposit closing balance increases by INR 3,000. Employer contributions do not reduce that net pay.

## Payslips and reports

Private downloadable payslips show employer/staff identity, period, attendance/paid days, component earnings, itemized deductions, gross/net, employer contributions separately and deposit opening/deducted/refunded/closing balances. Release only from authorized locked runs; version corrections visibly.

Reports: monthly salary register; department/branch/company cost; attendance/muster; late-coming; early-going; missing punches; overtime; leave balance/accrual/usage; PF statement including employee and employer split and ECR staging; ESI statement including employee/employer contributions; TDS statement, annual projection and filing staging; security deposit ledger; other deduction/advance/loan balances; bank transfer file and reconciliation; final settlement; accounting journal; approval/audit trail. PDF/CSV exports inherit the same permissions as the screen.

A statutory statement is not evidence of a return filed. Record prepared, accountant reviewed, exported, submitted and acknowledged separately. Government filing and bank execution are external integrations requiring independent validation.

## Data and operations

Core entities: Company, UserMembership, Staff, SalaryVersion, Component, ShiftAssignment, HolidayCalendar, DeviceMapping, RawPunch, AttendanceDay, Correction, LeavePolicyVersion, LeaveRequest, LeaveLedger, PayrollBatch, PayrollLine, StatutoryRuleVersion, DepositLedger, DeductionSchedule, PaymentInstruction and AuditEvent. Company-scoped identifiers/relations and private document storage are mandatory.

Encryption, least privilege, audit trails, documented retention, backups and restore drills are release requirements. Avoid sensitive data in logs; record privileged access. Target 500-staff monthly batch and realistic punch volumes; measure processing time and concurrency during implementation rather than claiming capacity from the plan.
