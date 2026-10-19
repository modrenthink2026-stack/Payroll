# Consolidated salary

Choose **Salary type → Consolidated salary — no PF / ESI** in initial salary entry or an increment recommendation, then enter the monthly consolidated amount and optional **HOD/Coordinator Allowances** separately. Basic, DA, HRA, CCA and other component fields are hidden. Gross equals the consolidated amount. Cum Gross = consolidated amount + HOD/Coordinator Allowances.

In **Salary Edit — department wise**, choose Consolidated for the selected staff row and enter its amount in **Allowances / Consolidated amount**. HOD/Coordinator Allowances remains editable; Basic, DA, HRA and CCA are disabled. Different staff in one department can use different salary types.

Consolidated versions prorate both the consolidated amount and HOD/Coordinator Allowances by paid days and exclude employee and employer PF/ESI contributions for those earnings. TDS, security deposit and other configured deductions retain their existing behavior. When a salary type changes during a month, payroll calculates each dated version separately and applies the existing contribution model only to component-based earnings.

Existing salaries default to Component-based. No staff have been converted automatically. Changes to an existing salary require a dated recommendation and the existing review/approval process. Saved payslips retain their historical amounts.

Salary CSV supports `salary_mode` (`component` or `consolidated`) and `consolidated_amount`. Basic is optional for consolidated rows; use `hod_allowance` for the separate HOD/Coordinator amount. PT and applicable security deposit use earned Cum Gross including this allowance.
