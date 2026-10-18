-- Optional dated salary eligibility; null retains the existing staff default.
alter table public.payroll_salaries add column deposit_eligible_override boolean;
alter table public.payroll_increments add column deposit_eligible_override boolean;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.dispatch(text,jsonb)'::regprocedure);
 if (length(src)-length(replace(src,'salary_mode,approved_by','')))/length('salary_mode,approved_by')<>3 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'salary_mode,approved_by','salary_mode,deposit_eligible_override,approved_by');
 if (length(src)-length(replace(src,'coalesce(payload->>''salary_mode'',''component''),uid','')))/length('coalesce(payload->>''salary_mode'',''component''),uid')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'coalesce(payload->>''salary_mode'',''component''),uid','coalesce(payload->>''salary_mode'',''component''),(payload->>''deposit_eligible_override'')::boolean,uid');
 if (length(src)-length(replace(src,'salary_mode,reason,created_by','')))/length('salary_mode,reason,created_by')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'salary_mode,reason,created_by','salary_mode,deposit_eligible_override,reason,created_by');
 if (length(src)-length(replace(src,'coalesce(payload->>''salary_mode'',''component''),payload->>''reason''','')))/length('coalesce(payload->>''salary_mode'',''component''),payload->>''reason''')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'coalesce(payload->>''salary_mode'',''component''),payload->>''reason''','coalesce(payload->>''salary_mode'',''component''),(payload->>''deposit_eligible_override'')::boolean,payload->>''reason''');
 if (length(src)-length(replace(src,'inc.hod_allowance,inc.salary_mode,uid','')))/length('inc.hod_allowance,inc.salary_mode,uid')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'inc.hod_allowance,inc.salary_mode,uid','inc.hod_allowance,inc.salary_mode,inc.deposit_eligible_override,uid');
 execute src;
end $patch$;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.calculate(uuid,date)'::regprocedure);
 if (length(src)-length(replace(src,'consolidated numeric;','')))/length('consolidated numeric;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'consolidated numeric;','deposit_base numeric; deposit_all boolean; consolidated numeric;');
 if (length(src)-length(replace(src,'consolidated=0;consolidated_days=0;','')))/length('consolidated=0;consolidated_days=0;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'consolidated=0;consolidated_days=0;','deposit_base=0;deposit_all=true;consolidated=0;consolidated_days=0;');
 if (length(src)-length(replace(src,'factor=units/ndays;paid=paid+units;lop=lop+(1-units);','')))/length('factor=units/ndays;paid=paid+units;lop=lop+(1-units);')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'factor=units/ndays;paid=paid+units;lop=lop+(1-units);','factor=units/ndays;paid=paid+units;lop=lop+(1-units);
   if coalesce(sal.deposit_eligible_override,p.deposit_eligible,false) then deposit_base=deposit_base+(sal.basic+sal.da+sal.hra+sal.cca+sal.other+sal.hod_allowance)*factor;else deposit_all=false;end if;');
 if (length(src)-length(replace(src,'gross=b+da+hra+cca+other+hod+consolidated;','')))/length('gross=b+da+hra+cca+other+hod+consolidated;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'gross=b+da+hra+cca+other+hod+consolidated;','gross=b+da+hra+cca+other+hod+consolidated;
  deposit_base=case when deposit_all then gross else round(deposit_base,2) end;');
 if (length(src)-length(replace(src,'case when p.deposit_eligible and coalesce','')))/length('case when p.deposit_eligible and coalesce')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'case when p.deposit_eligible and coalesce','case when coalesce');
 if (length(src)-length(replace(src,'least(gross*0.10,','')))/length('least(gross*0.10,')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'least(gross*0.10,','least(deposit_base*0.10,');
 execute src;
end $patch$;
notify pgrst,'reload schema';
