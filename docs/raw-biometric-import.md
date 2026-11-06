# Five-column biometric import and department register

HR / full-access company roles use **Attendance → Upload raw biometric file**. Accounts can view **Department biometric register** and export reports; staff and manager accounts cannot load this whole-company register.

Upload a CSV with `Emp ID,Emp Name,Log Date,Logtime,Type`. Excel users first save as CSV; XLSX is not parsed directly. Dates accept `18-Sep-26`, `2026-09-18`, or `18-09-2026`; times accept seconds and AM/PM. Types are IN / OUT. Biometric IDs remain text and match the selected company's Staff Master exactly. Names are verified, not used to guess identity. Department and assigned day shift come from Staff Master. The limit is 62,000 raw punches / 16 MB.

1. Choose the month, file and import reference; Validate file shows identity/date errors and a calculated report before any write.
2. Import raw punches preserves evidence and deduplicates an identical employee/date/time/direction. Import alone does not approve attendance.
3. From Department biometric register, HR can review and **Save complete new days** in bulk with one reason. Only new working-day entries with one IN, one OUT, a valid day shift, no approved leave and no manual punches qualify. Existing reviewed attendance is never overwritten. Multiple/missing punches, afternoon arrivals, early-morning departures and overnight shifts use the existing department attendance review. Missing data is not treated as absence automatically.
4. Monthly late decisions remain with assigned Principal / HR. The monthly 25-minute allowance covers whole late entries sorted ascending, separately per employee. The crossing occurrence proposes a half-day decision; unused seconds neither partially cover it nor carry forward. CL balance checks and LOP payroll effects remain in the existing authorized late-review flow.
5. Combined HR confirmation uses the existing backend gate for all attendance, leaves, late decisions and payable days. Existing finalized attendance and locked payroll cannot be edited through this feature.

## Reports

Detailed CSV: Department, Emp ID, Emp Name, Log Date, Shift Time, Logtime, Type, Late Minutes (HH:MM:SS), Total Late Minutes, Exemption / Bio LOP, Manual Entry, Review. Within each department and employee, late entries are sorted low to high, followed by non-late entries. Missing punches remain explicit. Employees with missing monthly evidence remain visible. The screen previews 200 rows; downloads contain all matching rows. Clear employee search and choose All departments for the full company report.

Employee summary and department summary separately show late totals, exempt incidents, proposed adjustment days, approved Bio LOP days and pending attendance rows. Pending raw calculations are visibly provisional. Holidays/approved leave are not charged a late penalty. Old whole-minute attendance retains its existing precision and source hash; new bulk-reviewed raw entries preserve exact seconds in the shift snapshot. Old approved reviews are never silently reinterpreted as second-precision reviews.

## Deployment and safeguards

The additive `payroll_raw_biometric` RPC reuses the existing `attendance_register_v1` permissions, module/release controls, company locks, stale-source checks, idempotency and audit trail. It does not enable modules for any company. If the register is disabled, the Platform Administrator must enable the existing tested register feature through the established release process. No service-role key or machine credential is used in the browser. Live device synchronization remains separate.

Checks: Node parser/report tests include the confirmed 01:06:13 example, exact 25:00/25:01 boundary, duplicate punches, tenant-specific identity matching, stale decisions, missing/overnight/manual exceptions and a 60,000-punch file. SQL fixtures verify second-precision and legacy hashes; the integration fixture runs entirely inside a rollback transaction.
