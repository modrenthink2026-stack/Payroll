# Platform administration

Payroll now has a separate Platform Administration panel for the platform owner. It is not the same as a company Administrator: company roles remain limited to their assigned company.

## One-time bootstrap

After applying `database/platform-admin-upgrade.sql`, explicitly register the platform owner in the database. Do not infer this from a company name or a user email:

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

Apply the migration after the existing payroll schema, access-scope upgrade and system-user upgrade. Test the owner account, a selected company, an untouched company, a paused company, a disabled module, and a normal company Administrator before release.
