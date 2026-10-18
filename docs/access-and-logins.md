# Company access and staff logins

| Role | Available screens |
| --- | --- |
| Staff | Own Leave Application, Leave Balances, My Payslips, Leave Rules, Holiday List |
| HR | Staff Entry, Attendance/Biometric Leave, Staff Leave Data and Approvals, Letters & Services |
| Principal / President / Administrator | Every module in their authorized company |

Accountant retains the accountant workflow. Director retains assigned approvals/team access so Principal leave can still reach Director. No role gains access to a company without membership. Full module access does not bypass the existing no-self-approval, assigned leave-office, payroll lock or independent financial review rules.

Staff/HR restrictions are enforced by role-checked API actions and direct table RLS, not just navigation. Staff cannot read attendance, personnel profiles, salary master, letters, assessments or other staff data; their payslips are limited to their own released/paid payroll lines and matching runs. HR cannot access payroll/salary master, assessments, increments, deposits, account management or company settings. HR personnel creation does not fabricate salary versions; an authorized full-access account sets salary separately.

Administrator can assign explicit Principal/President memberships through Company settings → Assign user role. Assigning the Principal or President approval office also confers full company access to that existing company member; assigning HR confers HR scope. Access changes take effect immediately through database checks. Titles imported as text never grant permissions automatically. Current office accounts have not been guessed or assigned.

## Name-based Login IDs and activation

246 existing staff have reserved unique name-based Login IDs. Duplicate names receive numeric suffixes. New staff receive an ID automatically. View IDs in Staff Master or export the Staff register. No real staff names or login lists belong in source control.

For staff whose accounts are not yet active, sign in with full company access, open Staff Master → Activate staff logins, review the company and pending count, and enter a temporary password of at least 12 characters.

Activation processes pending active staff in batches of 25. It creates a marked Supabase Auth identity with a reserved internal email for the username, binds it to exactly that staff/company record, and grants Staff membership. Source contact emails remain in the private personnel details. Existing linked accounts are skipped without resetting their passwords. A retry may reuse a previously created, still-pending marked identity without changing its original temporary password; use the original temporary password for that identity.

New users sign in with their issued Login ID, then set a personal password of at least 12 characters. Both API calls and direct RLS block payroll data until the mandatory change finishes. The server checks that activation is linked before updating the password, and clears the trusted app-metadata flag only after Auth confirms the password change. Existing email logins and Project Manager Auth settings/passwords are unchanged. Name-based identities have no mailbox; administrator-assisted Auth recovery is required for a forgotten name-login password.

The `payroll-accounts` Edge Function verifies the caller against Auth on every request and checks company authorization via the payroll RPC before using platform-managed Auth administration credentials. The gateway's legacy JWT-only option is off because the handler validates the real user with Auth, including newer signing keys; an unsigned live request returned 401. No credentials are logged, returned, committed or sent to a different service. Normal activation supports the permanent production and main-branch origins only.

## Validation

43 JavaScript tests, the production build, and seven rollback-only PostgreSQL suites passed. Tests cover the role/screen matrix, direct-RLS Staff/HR restrictions, own-only released payslips, full Principal/President access, company boundaries, office access revocation, duplicate-name IDs, exact staff/account binding and first-login API/RLS gates. Auth handler tests use mocked services; they verify authorization before privileged calls, rejection of short passwords, skipping linked identities, no reset on pending retries, and no gate clearing on failed password updates. An authenticated browser walkthrough was not performed.

Gauntlet benchmark: the user's access matrix and existing payroll invariants. The strongest adversarial findings were direct-RLS access before the first password change and a retry potentially resetting a previously created account. Role predicates now block temporary-password sessions, activation binding is checked before password changes, and pending-account retries never reset passwords; affected checks passed.
