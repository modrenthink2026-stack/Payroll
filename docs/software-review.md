# Current payroll software review — 13 October 2026

Based on inspected official product/help pages; not hands-on product trials or guaranteed plan availability. Exact biometric models, subscription limits and custom refundable deposit accounting require vendor confirmation. No vendor was contacted and no purchase was made.

| Product | Inspected capabilities | Relevance / limitation |
|---|---|---|
| greytHR | Payroll, leave, attendance, employee self-service; biometric attendance and shift/overtime reporting | Strong benchmark for payroll-first HR workflows. Validate custom deposit ledger and exact hardware compatibility. |
| Keka | Payroll/statutory reports, attendance, employee workflows; documented SQL, SDK, push and API biometric paths | Useful benchmark for staff/manager experience and biometric connector design. Hardware method depends on device; product marketing is not proof of a particular installation. |
| Zoho Payroll + Zoho People | Payslips, leave/attendance; People biometric API/plugin integration; payroll receives employee and loss-of-pay inputs | Useful modular ecosystem benchmark. People integration requires checking native leave/attendance configuration, not running both as conflicting attendance sources. |
| Pocket HRMS | Payroll, attendance, leave and employee self-service; vendor describes maintained statutory updates | Additional full HRMS benchmark. Exact connector and deposit workflow were not independently verified. |

No unsupported 'best' ranking: greytHR is the payroll/ESS reference, Keka the attendance/approval reference, and Zoho the modular-integration reference. Our proposed custom product will initially lag them in proven tax maintenance, established connectors and production support.

## Three viable delivery approaches

| Approach | Correctness and integrity | Effort / operations | Ownership / fit | Main dependency and failure mode |
|---|---|---|---|---|
| Configure a commercial HRMS | Mature workflows, subject to vendor configuration review | Lower custom build effort, recurring subscription | Less control over exact deposit/refund workflow | Contract must support required deposit accounting and devices; unsupported customization can force parallel spreadsheets |
| Build a custom modular application | Explicit company permissions, payroll snapshots and ledgers | Highest build/test/compliance-maintenance effort | Best control for an owned GitHub project | Maintained official rules and hardware SDK/API access; stale tax logic can produce incorrect payroll |
| Custom staff/attendance portal plus licensed payroll service | Vendor payroll plus custom staff experience | Moderate build effort, ongoing integration costs | Custom UX with outsourced tax maintenance | Accessible payroll API and reconciled identities; mismatched leave/payroll versions can corrupt net pay |

Selected for this request: separate custom project, initially a modular application with reviewed monthly runs and export staging. Reason: user explicitly wants a new GitHub project and specified a deposit workflow. Reassess the hybrid option before automating statutory filing if ongoing compliance maintenance cannot be staffed. Stack and hosting are intentionally not committed in this starter.

## Current statutory findings

EPFO's official September 2026 FAQ reports a ceiling change from INR 15,000 to INR 25,000 effective 17 September 2026 and gives split-month scenarios. This makes a single hardcoded PF ceiling unsuitable. Verify employee eligibility and the applicable notification when implementing; preserve historical rates.

ESIC's official contribution page lists employee 0.75% and employer 3.25%, and a daily-average-wage employee exemption. Production coverage, contribution-period continuity, eligible wage base and rounding need reviewed rule versions, not merely a percentage on gross.

The Ministry's labour-code FAQ describes the allowance add-back when specified exclusions exceed 50% of remuneration. It is not adequately modeled by forcing Basic to a fixed percentage. State, establishment and employment category must be established before deductions/leave rules are activated. Security deposit legality remains to be determined for the actual employer policy.

## Sources inspected

- https://www.greythr.com/employee-self-service-portal/
- https://www.greythr.com/attendance-management-software/
- https://www.keka.com/payroll-compliance
- https://help.keka.com/hc/en-us/articles/39946694933009-Getting-started-with-biometric-device-integration
- https://www.zoho.com/in/payroll/help/employer/leave-and-attendance/manage-attendance.html
- https://www.zoho.com/in/payroll/help/employer/integrations/integrations-people.html
- https://help.zoho.com/portal/en/kb/people/administrator-guide/attendance-management/biometric-device-integration/articles/biometric-device-integration-overview
- https://www.pockethrms.com/
- https://pmvbry-cdn.epfindia.gov.in/wp-content/uploads/2026/09/EPFO_Wage_Ceiling_FAQs.pdf
- https://esic.gov.in/contribution
- https://labour.gov.in/static/uploads/2026/01/de4758d5bfeffc456d7de97a801891b0.pdf

## Gauntlet review

Validated: requested-module coverage, template structure and illustration arithmetic; official/vendor source inspection. These are specification checks only.

Strongest challenge: gross-percentage deductions and current statutory constants could silently generate incorrect historical or unlawful payroll. Revision: separated deposit liability from TDS; added activation/legal-policy gate, caps/refunds, rule versioning, separate wage bases, split periods, review invalidation and locked snapshots. Completeness checks were rerun after revision.

Additional adversarial review: missing biometric punch is not absence; concurrent leave is not a safe read-then-write balance; exporting a bank/return file is not payment/filing. Added exception queues, atomic reservations and explicit reconciliation/acknowledgment states.

Decision: PASS WITH LIMITATIONS for the project specification. No application runtime, authentication, biometric compatibility, performance, legal deposit authorization, tax engine or filing has been tested. This is not a production-readiness verdict.
