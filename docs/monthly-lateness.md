# Monthly late-arrival review

Each staff member receives a strict **25 cumulative minutes per calendar month**. Sort positive late arrivals by minutes ascending, then date. Cover complete arrivals while they fit within 25 minutes. The first arrival that takes the sorted cumulative total above 25 is also subject to a half-day decision; there is no boundary exemption, partial coverage of an arrival or carry-forward to another month.

Examples:

- 2, 3, 10, 30 minutes: 15 minutes covered, 10 unused; the 30-minute arrival needs one 0.5-day decision.
- Confirmed October table: 117 total minutes, 24 covered, 1 unused. The 6-minute arrival on 20 October takes the cumulative total to 30 and is counted. Seven arrivals require decisions, totaling 3.5 days if all are assigned LOP.

## Use

1. Set each employee's actual reporting shift under Staff Master. The 08:00–14:30 example is not imposed on all staff.
2. Import biometric punches and record reviewed attendance. Raw punches still require HR review. Assigned-shift calculation preserves raw lateness before any daily grace, so the monthly policy does not grant a second allowance. Manual late-minute entries must be raw reviewed minutes. Historical rows without raw minutes fall back to stored reviewed minutes.
3. Open **Attendance → Monthly late review** or **Reports → Monthly late report** and choose the month.
4. The report shows Date, Day, Reporting Time, In Time, Late Minutes, Cumulative Late Minutes and decision. **In Time appears only for positive late arrivals**; early/on-time arrivals are absent from this list. Durations display as HH:MM. CSV includes the source times and numeric cumulative minutes.
5. The assigned company Principal or HR office holder chooses **0.5 day LOP or 0.5 day CL for each uncovered arrival**, with a reason. Administrators assign these existing confirmed company accounts under Leave & approvals → Assign leave approver. Module access follows the current role matrix in access-and-logins.md; self-review remains forbidden. No office accounts are inferred from job titles.
6. Recalculate payroll. Unresolved or stale late reviews create payroll exceptions and block approval. LOP reduces paid days and earnings; CL retains full pay and debits unreserved CL once. Payslips and salary CSV include the late totals and reviewed LOP/CL days.

Holidays, approved leave, absent/half-day attendance and dates outside employment are excluded from late penalties to prevent duplicate deductions. Early going remains separate. Reopening an unlocked review refunds its CL once and retains review history; attendance changes require reopening first. Changes to approved leave or working-day policy invalidate the source snapshot and require re-review. Locked, released or paid payroll cannot be changed through this workflow. The allowance remains fixed at 25 minutes.

## Validation

32 JavaScript tests and the static production build passed. Six rollback-only PostgreSQL suites passed, including the confirmed October example, the original example in a new month, raw minutes before daily grace, late-only In Time, authority and direct RLS, LOP salary arithmetic, CL full pay, retries, refunds, reserved CL, stale policy inputs, payroll locks and duplicate-penalty exclusions. Migration `payroll_strict_monthly_late_allowance` was applied successfully. Security advisor reported no new findings.

Gauntlet benchmark: the user's examples and strict 25-minute clarification plus a derived permission/ledger rubric. The strongest challenges were the threshold-crossing arrival and duplicate financial effects after attendance/leave changes. The confirmed crossing rule, snapshot validation, reopen/refund history, exclusion guards and retry checks address them. Tests used synthetic data and rolled back; no employee salary or leave decision was made. Signed-in browser interaction remains unverified.
