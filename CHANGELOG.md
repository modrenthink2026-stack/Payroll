# Changelog

## 2026-10-24

- Discard stale company responses and clear the previous workspace while loading.
- Require released payroll and server-checked payment eligibility for bank exports; remove the fallback that ignored holds.
- Preserve payment holds when installing platform controls, map hold actions to the payroll module and serialize module checks with company updates.
- Show platform infrastructure failures, respect module metadata and handle paused companies without crashing.
- Select the initial payroll month using India time.
- Repair Windows test harnesses and document a complete fresh install and additive existing-install migration.
- Add isolated SQL, migration-order and browser regression checks with synthetic data.
