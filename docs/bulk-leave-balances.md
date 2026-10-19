# Bulk opening / current leave balances

Open **Leave & approvals → Opening balances / bulk edit** as HR, Principal, President or Administrator.

1. Choose all departments or one department.
2. Select individual staff or select all displayed staff.
3. Enter actual remaining balances in the CL, EL, SL and custom paid leave columns. Existing balances are prefilled and shown below each entry. Inactive paid types remain available for reconciliation.
4. Enter the opening balance period or adjustment reason, then save.

Values are **target current balances**, not additional credits or annual entitlements. For example, changing CL from 12 to 8 posts a −4 day ledger adjustment. Zero explicitly clears a balance; a blank cell leaves that type unchanged. Enter at least one value for every selected staff member. Values use half-day steps from 0 to 9999.5 days.

This posts balances now; the reason can record the opening period but does not backdate a historical balance or overwrite earlier leave decisions/payroll. The annual entitlement in Leave Master is unchanged. No imported staff or balance values are included in the repository.

Only active staff in the chosen department/company can be updated. One save is atomic (maximum 500 staff / 50 paid leave types per staff), retains each change in the leave ledger and records an audit event. Duplicate retries do not credit again. Concurrent changes require reloading before saving. Targets below pending leave reservations are rejected. Unselected staff and omitted leave types are unchanged. The individual Credit / adjust balance option remains available for additive adjustments.
