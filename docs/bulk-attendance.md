# Department attendance entry / edit

Open **Attendance → Attendance bulk edit — department** as HR, Principal, President or Administrator.

1. Choose a department and date, then select **Load staff & attendance**.
2. Select individual staff or all loaded staff.
3. Edit each selected row: status, in/out times, raw late minutes, early-going minutes, calculation from shift, next-day out and row note.
4. Enter a review reason and save.

The editor loads the complete department/date directly from the server rather than using the recent 150-record list. It includes active staff whose employment dates cover that day. Existing values are prefilled. Unselected staff and other dates are unchanged. Changing department/date clears the draft.

Existing minutes are preserved by default. Tick **Calculate from shift** to use the staff member's current assigned shift and entered in/out times; both times are required. Use **Next-day out** for overnight duty. Shift calculation retains raw lateness for the 25-minute monthly allowance; daily early-going grace remains separate. This edits reviewed attendance, not biometric punch records.

One save is atomic for up to 500 selected staff. Each attendance write follows the existing permissions, employment-date, locked-payroll and completed late-review checks. Reopen a completed late review through the existing authorized workflow before editing its attendance. This feature never unlocks payroll or reopens reviews automatically. Changed attendance or staff/shift data requires reloading before save. Retrying the same saved request does not write twice. The review reason and row note are recorded with attendance and the batch is audited.
