# Platform administration

Payroll source includes a separate Platform Administration panel for the platform owner. Its backend was absent from the live database at the 24 October inspection; do not treat it as deployed until the repair migration is verified. It is not the same as a company Administrator: company roles remain limited to their assigned company.

## One-time bootstrap

For a fresh installation, use the complete SQL emitted by `node scripts/database-install.mjs`. Existing installations use `supabase/migrations/20261024123135_payroll_reliability.sql` after confirming system-user and payment-hold prerequisites; never replay the baseline or table-creating upgrades. See `operations.md` for installation details. After verifying the backend, explicitly register the platform owner in an authorized administrative session. Do not infer this from a company name or a user email:

```sql
insert into public.payroll_platform_admins(user_id, created_by)
values ('OWNER_AUTH_USER_UUID', 'OWNER_AUTH_USER_UUID');
```

The table is intentionally empty by default. This prevents every existing company Administrator from receiving cross-company access.

## What the panel controls

- Create payroll companies. New companies start with every module disabled.
- Activate or pause a company with optimistic revision protection.
- Enable or disable Staff, Attendance, Leave, Payroll, Letters, Assessments, Reports and Settings per company.
- Create or resume a company Administrator login with a temporary password. The account must change that password at first sign-in.
- Review company counts, access status and enabled modules.

Module and pause checks run in database RPCs. Hiding navigation is only a convenience; direct writes through the main and bulk RPCs are rejected when the company or module is unavailable. Existing records remain readable through the ordinary company role checks.

The repaired gateway composes the platform guard with `payment_dispatch`, preserving salary holds and payment reconciliation. Hold writes and history are mapped to the Payroll module, and bank eligibility requires released payroll. The isolated tests cover payment behavior after both platform/payment upgrade orders, paused and disabled payment controls, company-administrator isolation, and existing record readability. Test real owner access, a selected company, an untouched company and authenticated browser flows before release. Installing the backend never selects or grants an owner automatically.
