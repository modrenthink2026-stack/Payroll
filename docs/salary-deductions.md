# Salary-entry deductions

Consolidated and component-based salary entry both include **Professional Tax monthly amount** and **Security Deposit applicable**. The department editor has a field/checkbox for each selected staff row, plus a Security Deposit estimate.

Security Deposit is 10% of eligible earned salary, limited by the remaining approved company cap. Company settings must have the reviewed deposit policy enabled and a positive cap. The editor shows zero and a policy-disabled message when this is not configured. Consolidated salary excludes PF/ESI, while Security Deposit can still apply.

Professional Tax is a reviewed monthly amount entered by the employer/accountant. Leave it blank for active company PT slabs or the manual Tax Inputs default, enter zero for an exception with no PT, or enter a reviewed override. The latest applicable approved salary version in the payroll month supplies this monthly amount; it is not prorated by paid days. With automatic slabs enabled, PT is calculated from earned monthly Cum Gross instead; see professional-tax-slabs.md.

Changes to existing salary deductions are saved with the dated recommendation and apply after its existing review/approval process. Staff defaults are retained for salary versions without an explicit choice. Existing saved payroll lines are not rewritten.
