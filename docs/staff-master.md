# Staff master upload, editing, deletion and shifts

Implemented 16 October 2026. Access: company Administrator and HR. Employees, managers and accountants cannot mutate the staff master through these operations.

## Upload

Staff master → Download template → fill the CSV → Upload staff CSV → review preview → Confirm upload. Save Excel files as CSV first; XLSX import is not implemented. Use text formatting for staff codes, biometric IDs and bank account numbers to preserve leading zeros. Maximum 500 rows and 2 MB per batch.

Required columns: code, name, email, joining_date (YYYY-MM-DD), basic. Optional columns include department, designation, DA, HRA, other allowance, biometric ID, bank account, IFSC, PAN, UAN, ESI number, manager email, probation end, reviewed coverage flags and assigned shift settings. Downloaded headers use `da`, `hra`, `other`, `pf_enabled`, `esi_enabled` and `deposit_eligible`. Coverage flags default to false and accept true/false, yes/no or 1/0. Managers must already have the company Manager role.

Uploads create new records only. Duplicate codes/emails (case insensitive) and biometric IDs are rejected. No salary history is overwritten. The server saves the entire batch in one transaction and uses the same request identifier on a retry, preventing partial imports and retry duplication. No login accounts are created and no invitation emails are sent. Staff then use the existing verified-account onboarding flow. Uploaded files and previews are not saved to browser storage or GitHub.

## Edit and delete

Edit staff details, bank/statutory references and shift assignment from each row. Staff code, email and joining date remain read-only in the editor. Initial salary is entered on creation; revisions continue through the existing increment recommendation/review workflow.

Delete is restricted to unused, unlinked entries created in error, with staff-code confirmation. Accounts linked to staff, attendance, biometric punches, leave, payroll lines, deposits, letters, assessments, increments or multiple salary versions prevent deletion. Use the authorized separation workflow for employees who have left. Deleting a staff master never deletes an Auth account. All successful writes are recorded in the company audit log.

## Shift timings

Each staff record has a shift name, start/end time, break minutes, late grace and early-going grace. All times are India local time. Defaults are General 09:00–18:00 with zero break/grace; HR must review these before use. An end earlier than the start means next-day finish. Zero-duration shifts and breaks equal to or longer than the shift are invalid.

Attendance → Record attendance has an optional **Calculate late / early minutes from assigned shift** checkbox. In/out times are required for calculation. Select **Out time is on the following day** for overnight work. Server-calculated late/early minutes subtract the configured grace. The exact shift is saved with the attendance record; changing the staff shift does not recalculate historical attendance. Manual reviewed values remain available when calculation is unticked. Break duration is stored for shift planning; it does not automatically change paid days, overtime or salary. Rotating rosters, date-effective shift assignments and automatic biometric-to-attendance conversion remain future work.

## Current benchmark checked

Official Zoho documentation checked on 16 October 2026 supports employee imports with a preview/mapping process and shift start/end, attendance windows and grace policies:

- https://www.zoho.com/in/payroll/help/employer/import.html
- https://help.zoho.com/portal/en/kb/people/administrator-guide/shifts/settings/articles/shift-settings
- https://www.zoho.com/in/payroll/help/employer/leave-and-attendance/manage-attendance.html

Three import approaches were considered: direct overwrite (higher risk to salary history), previewed create-only batches (selected for safe initial enrollment), and field-mapped upserts (flexible but requires conflict and salary revision semantics). The current release uses the second approach and a fixed downloadable CSV template.

## Verification

18 unit tests passed; syntax checks and static production build passed. New database rollback scenarios passed: atomic import, request replay, case-insensitive duplicates, invalid shifts, overnight late/early calculation, shift snapshot preservation, staff-code confirmation, historical deletion block, company isolation and accountant denial. Existing payroll workflow and calculation edge-case suites also passed, with fixtures rolled back. No real staff records were uploaded or deleted.

Rendered browser validation remains incomplete: the cloud browser does not permit local-file previews and the connected Vercel team does not expose the Payroll project. The former Payroll branch URL could not be resolved through the Vercel connector. The GitHub push does not by itself prove a live deployment.

Database upgrade for an existing installation: `database/staff-master-upgrade.sql` (already applied to the authorized Supabase project). `database/payroll.sql` includes the same changes for fresh installations; never rerun the fresh-install schema on an existing database.
