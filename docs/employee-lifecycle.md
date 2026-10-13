# Employee lifecycle, letters and increment assessments

Scope extension: 13 October 2026. This is a specification, not implemented letter-generation software. 'Regularisation of service' means probation confirmation / conversion to confirmed service here; attendance regularisation remains a separate workflow. Company-specific policy can define other service conversions.

## Letters and related records

| Type | Data and workflow |
|---|---|
| Offer letter | Candidate, position, location, proposed joining date, component-wise salary/CTC, conditions, validity, signatory; acceptance, rejection, expiry and withdrawal |
| Appointment letter | Accepted offer or approved direct appointment, staff code, actual joining date, salary, reporting manager, probation and approved employment terms |
| Probation assessment | Review date, assessor, measurable goals, evidence, employee comments and recommendation: confirm, extend, or escalate for decision |
| Service confirmation / regularisation | Approved assessment, effective date, confirmed status and corresponding leave/benefit-policy changes |
| Probation extension | Approved reason, revised end date, improvement expectations and next review |
| Staff assessment / appraisal | Period, goals, weighted criteria, self-assessment, manager assessment, evidence, HR review and calibrated final result |
| Increment recommendation | Current/proposed salary components, increment amount/percentage, proposed effective date, rationale, budget and approval status |
| Increment letter | Authorized salary change, component breakdown, effective date and arrears treatment; issued only after salary version is approved |
| Promotion / transfer / redesignation | New role, grade, manager, company/branch, effective date and salary changes where approved |
| Resignation acceptance | Employee request, acceptance, notice dates, agreed last working date, handover and clearance requirements |
| Termination letter | Authorized separation case, approved reasons/wording, effective and notice dates, evidence references and signatory; restricted access |
| Relieving letter | Recorded separation, actual last working date, authorized clearance outcome and release confirmation |
| Experience letter | Verified employment dates, designation(s), work description and authorized signatory; separate from relieving and settlement |
| Other letters | Joining acknowledgment, employment/salary certificate, warning/show-cause, performance improvement plan, suspension/reinstatement, contract renewal, deputation and approved final-settlement statement |

Sensitive disciplinary and separation templates require reviewed wording suitable for the company, employment category and jurisdiction before use. No actual employee is appointed, incremented or terminated by this package; no letters have been sent.

## Letter Master and document controls

Configurable company letterhead, address, logo, numbering series, language, template version, authorized signatory, signature method and role access. Fields merge from verified records into a preview; required unresolved placeholders block issuance. HR can propose changes but cannot quietly edit approved terms.

Lifecycle: Draft → Review → Approved → Issued → Acknowledged; withdrawn or superseded versions remain in history. Employee acknowledgment and offer acceptance are different events. Recording an uploaded signature is distinct from a validated electronic-signature service. After issuance, save an immutable document with template/data snapshot, number, checksum, approver, issued timestamp and effective date. Correction creates a linked replacement rather than modifying the issued PDF.

PDF download and optional email delivery are planned. Email remains a separate authorized action with delivery status; generation does not send automatically. Candidate offer access uses an expiring restricted link. Active staff see released personal documents through their individual login; disciplinary evidence is limited to authorized HR/legal decision-makers. Separated staff may receive authorized documents through a verified channel without retaining full system access.

## Assessments and increment approval

Configurable criteria: performance, work quality, productivity, skills, responsibility, teamwork, conduct, goals and reviewed attendance. Choose rating scale, weights and review period per assessment master. For numeric scoring, weights total 100%; final score = sum(weight × rating) / 100. Missing mandatory ratings block finalization, not become zero. Attendance imports inform review but cannot automatically determine increment or disciplinary action.

States: Self Review / Manager Review → HR Review → Finalized. Staff can provide comments; retain each reviewer’s original input. Managers assess assigned staff only and cannot authorize their own increment. Recommendations show old/new Basic, DA, HRA and other allowance; gross increment = proposed recurring gross − current recurring gross. Percentage uses current recurring gross, with zero base flagged for review. Show employer-cost effect separately.

Increment recommendation → Manager recommendation → HR validation → Accountant checks cost, component classification and payroll effect → Authorized approver decision. Rejected/deferred decisions do not alter salary. Changed proposal invalidates approvals. Only an authorized salary-change record creates an effective-dated SalaryVersion, once; issued letters reference that record. Backdated changes calculate reviewed arrears/differences and statutory impact through adjustment payroll, not overwrite locked runs. Promotion and increment may be linked but remain distinct decisions.

## Service and separation controls

Service case: probation → confirmation / extension / other authorized decision. Scheduled effective dates are explicit; drafting a confirmation letter does not immediately change employment status or entitlements.

Exit case supports resignation, contract expiry, retirement, termination and other approved reasons. Distinguish decision date, letter issue date, last working date and access cutoff. Preparing or issuing a termination letter never automatically disables a staff account. Scheduled execution requires authorized separation decision and recorded cutoff; urgent security suspension is separately authorized and audited.

Clearance checklist tracks assets, access, handover, leave/attendance reconciliation, loans, advances and security deposit liability. Accountant prepares reviewed final settlement with earned salary, approved leave encashment, statutory deductions, notice adjustment if applicable, loan/advance balance, deposit refund and other lawful items. Asset non-clearance does not automatically permit withholding a deposit or wages; route disputes for an authorized reviewed decision. Experience-letter eligibility follows an approved policy independently from payment completion.

Final settlement uses payroll snapshots and reconciles deposit refunds exactly once. Separation does not delete salary, attendance, service or document history. Authentication cutoff must revoke active sessions and device attendance mapping as appropriate; released documents are delivered privately through authorized means.

## Data model and reports

Add Candidate, Offer, EmploymentEvent, DocumentTemplateVersion, EmployeeDocument, Acknowledgment, AssessmentCycle, AssessmentCriterion, AssessmentResponse, IncrementProposal, SalaryChangeApproval, SeparationCase and ClearanceItem. All reference company and employee/candidate ownership; generated files inherit document-specific access. Keep service changes as dated events and derive current status without losing earlier history.

Reports: pending offers/joinings; probation due/extended/confirmed; assessments due/completed; increment proposals and approved budget; salary before/after and arrears; promotion/transfer history; issued/pending/acknowledged letters; exits/clearances; final settlements and deposit refunds. Department reports avoid publishing individual salary to unauthorized managers.

## Proposed acceptance checks

1. An unresolved salary placeholder or missing signatory blocks letter issuance; candidate conversion does not create duplicate staff records.
2. Issued-document revision creates a new linked version; the old PDF and approval evidence remain unchanged.
3. Staff cannot download another person's letter by changing an identifier; confidential evidence is excluded from staff copies.
4. Assessment weights total 100%; mandatory ratings and evidence are checked; reassignment does not expose another company's staff.
5. Rejected/deferred increments do not change payroll; approving/retrying one increment creates exactly one salary version.
6. A mid-month increment splits earned components correctly; backdated change after lock becomes an adjustment, preserving released payslips.
7. Draft confirmation does not alter leave entitlement; approved effective-date event changes policy once and records balance adjustments.
8. Draft/issued termination letter alone does not disable login; approved access cutoff revokes sessions at the scheduled time.
9. Duplicate final-settlement execution cannot refund the deposit twice; issued letters never count as proof of payment.
10. Unapproved or incorrect-company terms cannot merge into appointment, termination or relieving documents.

## Gauntlet review of the extension

Strongest challenge: treating a generated letter as a salary or employment-status change would allow drafting errors to change payroll or disable access. Targeted revision: separated document issuance, authorized salary/service events, effective dates and access cutoff; added idempotent salary-change and refund criteria. Reviewed for consistency against locked-payroll, employee permissions and deposit-ledger requirements.

Three options considered: simple templates (fast but weak linkage/audit); external HR/e-sign service (established delivery/signature capabilities but API/cost/data dependencies); internal lifecycle records with versioned templates (more implementation effort but explicit links to payroll and permissions). Selected internal lifecycle records with optional future e-sign adapter. Benchmark: existing payroll invariants and the inspected HRMS workflow categories; no new vendor capability verification was performed for letter modules.

Decision: PASS WITH LIMITATIONS for the specification extension. Requirement/catalog coverage can be checked; PDF rendering, signature validity, delivery, runtime approval enforcement and company-specific legal wording remain unimplemented and untested.
