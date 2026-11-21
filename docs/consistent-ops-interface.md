# Consistent company interface and Ops

- `/ops` has a separate browser session and checks the existing canonical Platform Administrator registry before loading any company workspace. Company users retain their assigned username and first-password workflow.
- Company navigation groups only pages already permitted for the role. Hover opens submodules; leaving closes them; tapping the account button works without hover. Keyboard and outside-click dismissal remain available.
- Company Settings retains users and company policy controls. A JSON export includes the company records loaded by the authorized session. It is not a complete database backup: raw source uploads, private operational history and Auth credentials are excluded. Issued and locked payroll history is not erased by this interface.
- Ops retains company creation, module controls and initial Administrator setup, and adds private pass expiry and integration eligibility. Expiry is checked by the installed server feature gate; an unset expiry preserves access. Core module updates preserve add-on assignments that older clients do not display.
- Release Center uses the installed owner-only versioned release API, including test evidence, feature/grant revisions and master-company checks. No customer grant is created automatically by deployment.
- Integration eligibility is not provider connectivity. No third-party credentials are collected here.

Validation includes all unit tests, isolated Ops policy permission/CAS/expiry tests and menu DOM interaction tests. Existing attendance, leave, salary, payment hold and approval rules are retained.
