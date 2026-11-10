# Access protection review — 10 November 2026

Scope: Project Manager and the shared Supabase database used by Payroll. Read-only metadata, synthetic permission tests, current-source secret-pattern scan and available last-24-hours API logs were inspected. No customer database export or backup was created. No business records, memberships or passwords were changed.

## Findings

- All inspected application business tables have row-level security enabled. No anonymous table grants were present on PM/Payroll business tables. Key business RPCs reject anonymous execution.
- A synthetic unrelated authenticated subject could read zero company, payroll staff, salary or journal rows in live transaction-rolled-back checks. These are access-control checks, not an assertion that every authorized account is trusted.
- The available last-24-hours REST log aggregate contained authenticated requests and no anonymous business REST requests. This cannot prove absence of older access, use of compromised authorized credentials, copying through exports/screenshots, or access not retained in these logs.
- No supported-pattern secret API keys, service-role JWTs, GitHub tokens or private keys were found in the checked current source. A publishable API key is intentionally visible and does not authorize business data by itself. This is a pattern scan, not exhaustive proof that no secret has ever been exposed.
- Project Manager lacked CSP, anti-framing and other browser security headers. Added a same-origin script policy, explicitly allowed Supabase connections, denied embedded objects/framing, disabled referrer transmission and marked entry HTML non-cacheable. Inline CSS remains allowed because the existing React interface uses inline styles; inline scripts and eval are not allowed.
- Account helper functions did not explicitly reject banned/soft-deleted accounts; Payroll membership helpers also did not consistently require an existing Auth user. Existing signed tokens could remain meaningful until expiry. Hardened existing helper checks against live Auth identity state. Preserved temporary-password restrictions and all active-account roles.
- Compromised-password protection remains disabled on the shared Auth service. The connector has no Auth-settings update capability and the dashboard requires an authenticated administrator session. Enable this in the Supabase password-security settings if supported by the current plan; it is a separate account-level action. No billing or password changes were performed.
- Payroll's GitHub repository is public. Source code may be copied publicly. Repository visibility is distinct from access to the application database; making the repository private is an additional owner setting, not evidence that payroll data was disclosed.

## Changes and verification

In this repository, `database/account-security-upgrade.sql` updates Payroll role and platform-admin helpers. The corresponding Project Manager upgrade changes `private.pm_account_ready`. Both use definition hashes to stop an upgrade if the reviewed function has changed. Apply once to the reviewed schema; do not replay blindly in a fresh installation or downgrade to an older helper version.

Synthetic database checks reproduced the prior banned-account behavior and then verified denial for banned, soft-deleted, missing and temporary-password accounts, allowance for active/expired-ban accounts, and preserved memberships. Live metadata checks confirmed the installed guards and anonymous-denial settings. Frontend tests validate header policy and preserve proxy/no-store behavior; build and DOM checks cover login and accounting separately.

The site remains usable by authorized users. Users permitted to view data can still photograph or copy it; client-side removal of export buttons cannot prevent that. Strong administrator passwords, administrator MFA with a tested recovery flow, appropriate role assignment and account review remain important. MFA was not silently forced because neither application currently provides the necessary enrollment/challenge flow.

Verdict: protection improved; no evidence from these limited checks establishes that an outsider copied data, and no absolute safety guarantee is made. Historical forensic coverage and account-setting actions remain limited.
