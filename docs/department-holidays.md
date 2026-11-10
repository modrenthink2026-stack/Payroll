# Department holiday calendar

The database migration is applied and the feature is enabled for Payroll Demo only. No holiday dates are prefilled.

HR and full-access company roles can open **Holiday list**, add a name and inclusive date range, and choose All departments or Selected departments. They can edit or cancel entries. Cancellation retains history and permits restoration through Edit. Staff see common holidays and their own department's active entries.

Existing company dates remain common holidays. The calendar is additive: existing weekly offs and common holidays are retained, overlapping holidays are counted once, and selected department holidays do not change other departments. An empty Selected departments choice is rejected; it never becomes an all-company holiday.

The migration adds private calendar/history tables and an authenticated, company-scoped RPC. It integrates the working-day rule into attendance, leave application unit counts, monthly late planning and salary calculation. Attendance-period, late-review and payroll fingerprints reflect applicable calendar changes. Companies without `settings.department_holidays_enabled=true` retain their previous calculations and hashes. No holiday records or policy settings are inserted by the migration.

Holiday changes are blocked for affected confirmed attendance or locked/released/paid payroll months, and when affected submitted/approved leave exists. Resolve or reopen those workflows first. Holidays do not automatically approve attendance, debit leave, approve payroll or execute payment.

Deployment sequence: apply the guarded migration, run the hosted rollback fixture, enable the calendar for the selected test company, and publish the frontend. The core version guard rejects concurrent function changes; rebuild and review the migration if it fires.

Validation:

- `npm test`: client domain, rendering, escaping, role navigation and existing regression checks.
- `node tests/department-holidays-db.mjs`: isolated PostgreSQL integration with a metadata-only schema fixture and controlled module/feature flags. No production data is copied. It tests department scope, common dates, range endpoints, company isolation, staff write denial, stale revisions, approval/confirmation locks, late exemptions, leave-day counting, payroll holiday pay and cancellation history.
- `tests/integration/department-holidays.sql`: the same synthetic rollback checks for the hosted schema after approved deployment.

Both the isolated test and the hosted synthetic rollback fixture passed. The isolated fixture controls release/module flags. A signed-in browser check remains separate from database verification.
