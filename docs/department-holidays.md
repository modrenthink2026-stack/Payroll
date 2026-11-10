# Department holiday calendar

Status: implemented on the feature branch; database deployment and Demo enablement await explicit approval after automatic deployment review rejected the core payroll migration.

HR and full-access company roles can open **Holiday list**, add a name and inclusive date range, and choose All departments or Selected departments. They can edit or cancel entries. Cancellation retains history and permits restoration through Edit. Staff see common holidays and their own department's active entries.

Existing company dates remain common holidays. The calendar is additive: existing weekly offs and common holidays are retained, overlapping holidays are counted once, and selected department holidays do not change other departments. An empty Selected departments choice is rejected; it never becomes an all-company holiday.

The migration adds private calendar/history tables and an authenticated, company-scoped RPC. It integrates the working-day rule into attendance, leave application unit counts, monthly late planning and salary calculation. Attendance-period, late-review and payroll fingerprints reflect applicable calendar changes. Companies without `settings.department_holidays_enabled=true` retain their previous calculations and hashes. No holiday records or policy settings are inserted by the migration.

Holiday changes are blocked for affected confirmed attendance or locked/released/paid payroll months, and when affected submitted/approved leave exists. Resolve or reopen those workflows first. Holidays do not automatically approve attendance, debit leave, approve payroll or execute payment.

After approval, apply `supabase/migrations/20261110075724_department_holidays.sql`, run the hosted rollback integration fixture, and enable only Payroll Demo's `department_holidays_enabled` setting. The other company settings remain unchanged. Publish the frontend after the backend is verified.

Validation:

- `npm test`: client domain, rendering, escaping, role navigation and existing regression checks.
- `node tests/department-holidays-db.mjs`: isolated PostgreSQL integration with a metadata-only schema fixture and controlled module/feature flags. No production data is copied. It tests department scope, common dates, range endpoints, company isolation, staff write denial, stale revisions, approval/confirmation locks, late exemptions, leave-day counting, payroll holiday pay and cancellation history.
- `tests/integration/department-holidays.sql`: the same synthetic rollback checks for the hosted schema after approved deployment.

The isolated test controls the existing release/module flags. Full hosted integration and a browser check of the deployed calendar remain pending; local tests do not establish deployment success.
