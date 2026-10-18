# Consolidated salary

Choose **Salary type → Consolidated salary — no PF / ESI** in initial salary entry or an increment recommendation, then enter the single monthly amount. Basic, DA, HRA, CCA and other component fields are hidden. Gross and Cum Gross equal the consolidated amount.

In **Salary Edit — department wise**, choose Consolidated for the selected staff row and enter its amount in **Allowances / Consolidated amount**. The other component cells are disabled. Different staff in one department can use different salary types.

Consolidated versions prorate the amount by paid days and exclude employee and employer PF/ESI contributions for those earnings. TDS, security deposit and other configured deductions retain their existing behavior. When a salary type changes during a month, payroll calculates each dated version separately and applies the existing contribution model only to component-based earnings.

Existing salaries default to Component-based. No staff have been converted automatically. Changes to an existing salary require a dated recommendation and the existing review/approval process. Saved payslips retain their historical amounts.

Salary CSV supports `salary_mode` (`component` or `consolidated`) and `consolidated_amount`. Basic is optional for consolidated rows.
