-- Optional reviewed monthly Professional Tax amount. Null follows accountant Tax Inputs.
alter table public.payroll_salaries add column pt_override numeric(14,2) check(pt_override>=0);
alter table public.payroll_increments add column pt_override numeric(14,2) check(pt_override>=0);
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.dispatch(text,jsonb)'::regprocedure);
 if (length(src)-length(replace(src,'deposit_eligible_override,approved_by','')))/length('deposit_eligible_override,approved_by')<>3 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'deposit_eligible_override,approved_by','deposit_eligible_override,pt_override,approved_by');
 if (length(src)-length(replace(src,'(payload->>''deposit_eligible_override'')::boolean,uid','')))/length('(payload->>''deposit_eligible_override'')::boolean,uid')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'(payload->>''deposit_eligible_override'')::boolean,uid','(payload->>''deposit_eligible_override'')::boolean,nullif(payload->>''pt_override'','''')::numeric,uid');
 if (length(src)-length(replace(src,'deposit_eligible_override,reason,created_by','')))/length('deposit_eligible_override,reason,created_by')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'deposit_eligible_override,reason,created_by','deposit_eligible_override,pt_override,reason,created_by');
 if (length(src)-length(replace(src,'(payload->>''deposit_eligible_override'')::boolean,payload->>''reason''','')))/length('(payload->>''deposit_eligible_override'')::boolean,payload->>''reason''')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'(payload->>''deposit_eligible_override'')::boolean,payload->>''reason''','(payload->>''deposit_eligible_override'')::boolean,nullif(payload->>''pt_override'','''')::numeric,payload->>''reason''');
 if (length(src)-length(replace(src,'inc.salary_mode,inc.deposit_eligible_override,uid','')))/length('inc.salary_mode,inc.deposit_eligible_override,uid')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'inc.salary_mode,inc.deposit_eligible_override,uid','inc.salary_mode,inc.deposit_eligible_override,inc.pt_override,uid');
 execute src;
end $patch$;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.calculate(uuid,date)'::regprocedure);
 if (length(src)-length(replace(src,'deposit_base numeric;','')))/length('deposit_base numeric;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'deposit_base numeric;','monthly_pt numeric; deposit_base numeric;');
 if (length(src)-length(replace(src,'coalesce(p.pt,0)','')))/length('coalesce(p.pt,0)')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'coalesce(p.pt,0)','monthly_pt');
 if (length(src)-length(replace(src,'deductions=pf+esi+tds+deposit+','')))/length('deductions=pf+esi+tds+deposit+')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'deductions=pf+esi+tds+deposit+','monthly_pt=coalesce((select v.pt_override from public.payroll_salaries v where v.staff_id=s.id and v.effective_from<=least(last_day,coalesce(s.leaving_date,last_day)) order by v.effective_from desc limit 1),p.pt,0);
  deductions=pf+esi+tds+deposit+');
 execute src;
end $patch$;
notify pgrst,'reload schema';
