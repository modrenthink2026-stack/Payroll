# Company leave approvals

Released routing:

| Applicant group | Approval office |
| --- | --- |
| Teacher / Staff | Principal |
| Principal | Director |
| Director | President |
| Substaff / Aayah / Attender / Security | HR |

Administrator: open **Leave & approvals → Assign leave approver**. Assign one confirmed, active company account to each of the four offices. These offices are separate from payroll roles; a Principal can retain Staff access and see only their own personnel/payroll records plus leave requests assigned to that office. Assignment does not create an account, grant salary access, or send email. Accounts must already belong to the selected company. Blank email clears an office. All offices initially require administrator setup; imported titles never automatically grant approval authority.

HR / Administrator: use **Staff Master → Leave routing** to review a staff member's group. Automatic classification recognizes exact Principal, Director and President designations; support keywords in designation, department or employment category include Substaff, Aayah/Ayah/Aaya, Attender/Attendant and Security. Other staff route to Principal. Review compound titles and ambiguous classifications manually. An explicit group takes precedence. The President's own leave has no configured policy and cannot be submitted until a separate policy is agreed.

Each new request records its approval office. Group/designation changes affect future requests; existing requests retain their office. Reassigning an office moves its queue to the new active office holder immediately. Applicant and approver must be different people. There is no administrator/HR/manager approval bypass. Missing, inactive or self-directed approvers block submission with an actionable message.

Approvers use **Leave & approvals** to approve or reject submitted requests, or cancel approved requests. Payroll locks still prevent changes. Approval debits paid leave once; cancellation restores it once. Staff can withdraw their own pending requests. Notifications are in-app; no email or SMS delivery is implemented.

## Verification, 18 October 2026

26 JavaScript tests and production build passed. The new rollback-only PostgreSQL suite exercised all eight applicant categories, cross-company assignment denial, unassigned administrator and wrong-HR denial, approver queue visibility, direct RLS, salary/personnel isolation, approval/rejection/cancellation arithmetic, duplicate decisions, recorded-office stability, office reassignment, missing/self-approval guards and payroll locks. All four existing database regression suites passed after updating the synthetic leave fixture to configure its Principal office explicitly. No real employee leave decisions were made by these tests.

Gauntlet benchmark: the user's routing matrix plus a derived permission rubric (tenant isolation, no self-approval, limited data exposure and atomic balances). Comparing title-based payroll roles, individual reporting-manager mapping and separate company approval offices favored separate offices: it preserves the existing payroll roles, supports succession and limits approver data access. The strongest adversarial challenge was the old administrator/HR approval bypass and the temptation to expose whole staff records to approvers. Both were removed for leave decisions, and RPC/direct-table tests verified the result. Readiness was also tightened so an inactive/unlinked Staff account cannot appear configured. A fresh-install grant-order issue found in the final review was corrected, and private salary/personnel fixtures were added to make the privacy checks detect real leaks.

Signed-in browser interaction remains unverified; the release's database flows and frontend build were verified. Actual office accounts must be assigned by the company administrator before use.
