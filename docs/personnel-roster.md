# Full personnel roster

The roster importer supports the 73 source headers in `public/roster.js`, alongside the existing salary CSV format. Header metadata and synthetic tests are committed; real employee records must never be committed.

Staff Code, Staff Name and Date Of Joining identify each staff record. The importer recognizes ISO dates and DD-Mmm-YY dates, with a documented fixed two-digit-year pivot: 00–26 maps to 2000–2026; 27–99 maps to 1927–1999. Ambiguous dates outside this source convention should be converted to four-digit ISO years before upload.

The importer combines repeated staff codes only when all fields other than serial number and Security Deposit agree. It retains every original row. Conflicting duplicates are rejected for review. Existing staff codes are never overwritten. Source security deposits, dates and payment modes are reference information, not posted financial balances.

A new RLS-protected personnel table stores personal, family, address, identity, qualification and legacy labels. Only company HR/administrators and the staff member linked to their own record may read it. Accountants and managers do not receive this table through state responses or direct RLS reads. Existing bank/statutory payroll profiles retain their current access controls.

Source Email remains a contact field. Roster imports do not set a login email or link/create Auth users. HR must review and set a unique individual login email separately. Legacy UserType Name and AccessLevel never set authorization roles. Source data is never used to make employment decisions automatically.

No salary, statutory coverage, shift assignment, leave opening balance or deposit ledger amount is inferred from a personnel-only file. Staff show Salary not set and have a reviewed initial-salary action; later changes retain the increment approval workflow. General shift defaults must be reviewed separately. Employment Status/Category are retained as source classifications; service review is marked imported rather than inferring a confirmation decision.

## Approved database upgrade

`database/personnel-roster-upgrade.sql` adds:

- Nullable login email for staff who have no reviewed login address.
- ERP code and employment classification columns.
- The new personnel details table with RLS and restricted reads.
- Extensions to the central dispatcher for roster import, personnel editing, controlled login-email editing and reviewed initial salary.

The replacement function is based on the previously deployed dispatch body, verified by its hash before editing. Existing payroll calculation, payroll approval, biometric processing and company-role policies are not intentionally changed. Nevertheless, replacing the shared dispatcher can affect existing workflows and requires database regression tests before release.

The owner explicitly approved the upgrade on 18 October 2026 after reviewing its scope in PR #1. It has been applied to the authorized Supabase project. The approved personnel batch was first validated in a rollback transaction, then imported into the selected company. Full source rows remain in the protected database, outside GitHub. No Auth accounts, login links, salary amounts, statutory coverage or deposit ledger entries were inferred.

Validation executed: 23 unit tests, JavaScript syntax and static build passed. All four database rollback suites passed: roster privacy/import invariants, staff master/shift guards, payroll workflow and payroll edge cases. The full source batch passed checks for staff counts, source-row counts, all 73 fields, and absence of invented salary/login data before saving. The security advisor reported no new findings. Signed-in browser validation remains separate from these database checks.
