# Monthly late-arrival review — draft

Work in progress; not deployed and no database migration has been applied.

Requested report columns: Date, Day, Reporting Time, In Time, Late Minutes, Cumulative Late Minutes, and Principal/HR decision. In Time appears only for positive late arrivals. Early/on-time arrivals are excluded from this late-arrival list. Sort late arrivals by minutes ascending, then date; cumulative minutes follow that order. Show durations as HH:MM.

The draft allocates a 25-minute allowance to complete arrivals and proposes a separate 0.5 day LOP or CL decision for each uncovered arrival. Principal/HR decisions are explicit, with no self-review, no guessed financial decisions, no automatic CL choice, a pending-review payroll exception and an audited reopen/refund path. Raw lateness is retained before daily grace; existing reviewed attendance without raw minutes falls back to its reviewed late minutes. Holidays, approved leave, absence and already half-day dates are excluded from the late penalty list to prevent duplicate deductions.

Unresolved policy: in the user's October table, cumulative lateness reaches 30 minutes on 20 October, but that arrival has no LOP marker. The next six arrivals are marked LOP. Counting the crossing arrival gives seven half-day decisions (3.5 days); exempting it gives six (3 days). The implementation must be reconciled with the user's answer before release. Do not apply salary/leave changes based on the current draft.

Validation: 31 JavaScript unit tests and the static production build pass. A test confirms early/on-time In Time values are omitted and late values retain the sorted cumulative total. New database behavior and signed-in UI have not been verified. The attempted migration failed with an expired request state; a subsequent read-only check confirmed no late-review table or raw-late column was created and the live dispatcher remained unchanged.

Gauntlet benchmark: user's supplied examples and table. Strongest challenge: the conflicting boundary penalty changes salary by half a day; this is a release blocker pending clarification. No real employee data, decisions, or account permissions were changed.
