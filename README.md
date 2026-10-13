# Payroll Manager — project starter

Started: 13 October 2026. Owner account confirmed: modrenthink2026-stack.

Status: requirements and implementation planning starter, not an operational payroll application. Repository: https://github.com/modrenthink2026-stack/Payroll. No database, login service, deployment, live biometric connector, or statutory filing has been created.

Confirmed scope: India payroll; 101–500 staff; individual staff logins; eSSL / ZKTeco attendance; security deposit at 10% of earned gross salary. Exact device model remains unknown. Multi-company support is a proposed default, with strict company separation; confirm company/state list before implementation.

## Contents

- docs/requirements.md: modules, calculation rules, roles, workflows and safeguards.
- docs/software-review.md: current vendor benchmarks, sources and architecture choices.
- docs/backlog.md: ordered build milestones and proposed acceptance tests.
- docs/employee-lifecycle.md: offers, appointments, assessments, increments, confirmation and exit letters with approval/payroll links.
- templates/: blank staff, attendance, leave, assessment, increment and letter-register CSV templates.
- checks/validate_starter.py: document/template completeness and illustration checks only.

This project is separate from the existing construction project. The repository currently contains planning documents and blank templates. Do not upload real employee salary, bank, PAN, or identity data into GitHub.

Run starter checks with `python3 checks/validate_starter.py` from this directory. These checks do not validate payroll software, tax computations, authentication or device compatibility.
