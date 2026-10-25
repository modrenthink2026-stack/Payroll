# Changelog

## 2026-10-25

- Upload biometric absence, late-coming and early-going CSV reports into department/date attendance review, with exact biometric ID matching, date-range headings and times with seconds.
- Require an explicit reviewed status for missing-punch, afternoon-arrival and morning-departure cases; keep raw punches separate and preserve combined arrival/departure edits.
- Preserve the existing attendance save, company permissions, stale-data checks, payroll locks and monthly late-review rules; no database migration is required.
- Refresh staff settings before report preparation and discard superseded uploads or responses from a closed editor.
- Verify the report imports with 115 unit tests, 21 isolated SQL suites, Chrome browser checks against a mocked backend and the production build.
- Refresh dashboard cards, pending-work summaries, navigation, login and table styling.
- Add a labelled mobile module selector using the same company and role permissions as desktop navigation.
- Keep staff names and column headings visible when scrolling long staff tables, with larger touch controls and responsive payroll-month actions.
- Verify desktop, 390px and 320px layouts, mobile module selection and staff-table scrolling in Chrome.

## 2026-10-24

- Discard stale company responses and clear the previous workspace while loading.
- Require released payroll and server-checked payment eligibility for bank exports; remove the fallback that ignored holds.
- Preserve payment holds when installing platform controls, map hold actions to the payroll module and serialize module checks with company updates.
- Show platform infrastructure failures, respect module metadata and handle paused companies without crashing.
- Select the initial payroll month using India time.
- Repair Windows test harnesses and document a complete fresh install and additive existing-install migration.
- Add isolated SQL, migration-order and browser regression checks with synthetic data.
