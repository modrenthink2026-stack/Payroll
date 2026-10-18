-- Versioned consolidated pay. Other stores the single consolidated amount only for this explicit mode.
alter table public.payroll_salaries
 add column salary_mode text not null default 'component' check(salary_mode in ('component','consolidated')),
 add column consolidated_amount numeric(14,2) generated always as (case when salary_mode='consolidated' then other else 0 end) stored,
 add constraint payroll_salaries_consolidated_valid check(salary_mode<>'consolidated' or (basic=0 and da=0 and hra=0 and cca=0 and hod_allowance=0));
alter table public.payroll_increments
 add column salary_mode text not null default 'component' check(salary_mode in ('component','consolidated')),
 add column consolidated_amount numeric(14,2) generated always as (case when salary_mode='consolidated' then other else 0 end) stored,
 add constraint payroll_increments_consolidated_valid check(salary_mode<>'consolidated' or (basic=0 and da=0 and hra=0 and cca=0 and hod_allowance=0));
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.dispatch(text,jsonb)'::regprocedure);
 if (length(src)-length(replace(src,'other,cca,hod_allowance,approved_by','')))/length('other,cca,hod_allowance,approved_by')<>3 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'other,cca,hod_allowance,approved_by','other,cca,hod_allowance,salary_mode,approved_by');
 if (length(src)-length(replace(src,'coalesce((payload->>''hod_allowance'')::numeric,0),uid','')))/length('coalesce((payload->>''hod_allowance'')::numeric,0),uid')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'coalesce((payload->>''hod_allowance'')::numeric,0),uid','coalesce((payload->>''hod_allowance'')::numeric,0),coalesce(payload->>''salary_mode'',''component''),uid');
 if (length(src)-length(replace(src,'other,cca,hod_allowance,reason,created_by','')))/length('other,cca,hod_allowance,reason,created_by')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'other,cca,hod_allowance,reason,created_by','other,cca,hod_allowance,salary_mode,reason,created_by');
 if (length(src)-length(replace(src,'coalesce((payload->>''hod_allowance'')::numeric,0),payload->>''reason''','')))/length('coalesce((payload->>''hod_allowance'')::numeric,0),payload->>''reason''')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'coalesce((payload->>''hod_allowance'')::numeric,0),payload->>''reason''','coalesce((payload->>''hod_allowance'')::numeric,0),coalesce(payload->>''salary_mode'',''component''),payload->>''reason''');
 if (length(src)-length(replace(src,'inc.other,inc.cca,inc.hod_allowance,uid','')))/length('inc.other,inc.cca,inc.hod_allowance,uid')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'inc.other,inc.cca,inc.hod_allowance,uid','inc.other,inc.cca,inc.hod_allowance,inc.salary_mode,uid');
 if (length(src)-length(replace(src,' -- Lock company first for all writes.','')))/length(' -- Lock company first for all writes.')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,' -- Lock company first for all writes.',' if action in (''staff_save'',''initial_salary'',''increment_save'') and payload->>''salary_mode''=''consolidated'' then
  payload=payload||jsonb_build_object(''basic'',0,''da'',0,''hra'',0,''cca'',0,''hod_allowance'',0,''other'',coalesce(payload->>''consolidated_amount'',payload->>''other'',''0''));
 end if;
 -- Lock company first for all writes.');
 execute src;
end $patch$;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.calculate(uuid,date)'::regprocedure);
 if (length(src)-length(replace(src,'cca numeric; hod numeric;','')))/length('cca numeric; hod numeric;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'cca numeric; hod numeric;','consolidated numeric; consolidated_days numeric; stat_wage numeric; cca numeric; hod numeric;');
 if (length(src)-length(replace(src,'cca=0;hod=0;b=0;','')))/length('cca=0;hod=0;b=0;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'cca=0;hod=0;b=0;','consolidated=0;consolidated_days=0;cca=0;hod=0;b=0;');
 if (length(src)-length(replace(src,'other=other+sal.other*factor;','')))/length('other=other+sal.other*factor;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'other=other+sal.other*factor;','if sal.salary_mode=''consolidated'' then consolidated=consolidated+sal.other*factor;consolidated_days=consolidated_days+1;else other=other+sal.other*factor;end if;');
 if (length(src)-length(replace(src,'gross=b+da+hra+cca+other+hod;','')))/length('gross=b+da+hra+cca+other+hod;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'gross=b+da+hra+cca+other+hod;','consolidated=round(consolidated,2);gross=b+da+hra+cca+other+hod+consolidated;');
 if (length(src)-length(replace(src,'wage=greatest(b+da,gross/2);','')))/length('wage=greatest(b+da,gross/2);')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'wage=greatest(b+da,gross/2);','wage=greatest(b+da,gross/2);stat_wage=greatest(b+da,(gross-consolidated)/2);');
 if (length(src)-length(replace(src,'least(wage,','')))/length('least(wage,')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'least(wage,','least(stat_wage,');
 if (length(src)-length(replace(src,'ceil(wage*','')))/length('ceil(wage*')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'ceil(wage*','ceil(stat_wage*');
 if (length(src)-length(replace(src,'jsonb_build_object(''Basic'',b,''DA'',da,''HRA'',hra,''CCA'',cca,''Allowances'',other,''HOD/Coordinator Allowances'',hod)','')))/length('jsonb_build_object(''Basic'',b,''DA'',da,''HRA'',hra,''CCA'',cca,''Allowances'',other,''HOD/Coordinator Allowances'',hod)')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'jsonb_build_object(''Basic'',b,''DA'',da,''HRA'',hra,''CCA'',cca,''Allowances'',other,''HOD/Coordinator Allowances'',hod)','(case when consolidated_days=0 or b+da+hra+cca+other+hod>0 then jsonb_build_object(''Basic'',b,''DA'',da,''HRA'',hra,''CCA'',cca,''Allowances'',other,''HOD/Coordinator Allowances'',hod) else ''{}''::jsonb end)||(case when consolidated_days>0 then jsonb_build_object(''Consolidated salary'',consolidated) else ''{}''::jsonb end)');
 execute src;
end $patch$;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.department_salaries(jsonb)'::regprocedure);
 if (length(src)-length(replace(src,' for j in select * from jsonb_array_elements(payload->''rows'') loop','')))/length(' for j in select * from jsonb_array_elements(payload->''rows'') loop')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,' for j in select * from jsonb_array_elements(payload->''rows'') loop',' for j in select * from jsonb_array_elements(payload->''rows'') loop
  if j->>''salary_mode''=''consolidated'' then j=j||jsonb_build_object(''basic'',0,''da'',0,''hra'',0,''cca'',0,''hod_allowance'',0,''other'',coalesce(j->>''consolidated_amount'',j->>''other'',''0''));end if;');
 execute src;
end $patch$;
notify pgrst,'reload schema';
