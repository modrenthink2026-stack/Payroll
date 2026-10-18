-- Add salary components without changing stored payroll history.
alter table public.payroll_salaries
 add column cca numeric(14,2) not null default 0 check(cca>=0),
 add column hod_allowance numeric(14,2) not null default 0 check(hod_allowance>=0),
 add column gross numeric(14,2) generated always as (basic+da+hra+cca+other) stored,
 add column cum_gross numeric(14,2) generated always as (basic+da+hra+cca+other+hod_allowance) stored;
alter table public.payroll_increments
 add column cca numeric(14,2) not null default 0 check(cca>=0),
 add column hod_allowance numeric(14,2) not null default 0 check(hod_allowance>=0),
 add column gross numeric(14,2) generated always as (basic+da+hra+cca+other) stored,
 add column cum_gross numeric(14,2) generated always as (basic+da+hra+cca+other+hod_allowance) stored;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.dispatch(text,jsonb)'::regprocedure);
 if (length(src)-length(replace(src,'effective_from,basic,da,hra,other,approved_by','')))/length('effective_from,basic,da,hra,other,approved_by')<>3 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'effective_from,basic,da,hra,other,approved_by','effective_from,basic,da,hra,other,cca,hod_allowance,approved_by');
 if (length(src)-length(replace(src,'(payload->>''other'')::numeric,uid','')))/length('(payload->>''other'')::numeric,uid')<>2 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'(payload->>''other'')::numeric,uid','(payload->>''other'')::numeric,coalesce((payload->>''cca'')::numeric,0),coalesce((payload->>''hod_allowance'')::numeric,0),uid');
 if (length(src)-length(replace(src,'effective_from,basic,da,hra,other,reason,created_by','')))/length('effective_from,basic,da,hra,other,reason,created_by')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'effective_from,basic,da,hra,other,reason,created_by','effective_from,basic,da,hra,other,cca,hod_allowance,reason,created_by');
 if (length(src)-length(replace(src,'(payload->>''other'')::numeric,payload->>''reason''','')))/length('(payload->>''other'')::numeric,payload->>''reason''')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'(payload->>''other'')::numeric,payload->>''reason''','(payload->>''other'')::numeric,coalesce((payload->>''cca'')::numeric,0),coalesce((payload->>''hod_allowance'')::numeric,0),payload->>''reason''');
 if (length(src)-length(replace(src,'inc.basic,inc.da,inc.hra,inc.other,uid','')))/length('inc.basic,inc.da,inc.hra,inc.other,uid')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'inc.basic,inc.da,inc.hra,inc.other,uid','inc.basic,inc.da,inc.hra,inc.other,inc.cca,inc.hod_allowance,uid');
 execute src;
end $patch$;
do $patch$ declare src text; begin
 src=pg_get_functiondef('payroll_private.calculate(uuid,date)'::regprocedure);
 if (length(src)-length(replace(src,'b numeric; da numeric; hra numeric; other numeric;','')))/length('b numeric; da numeric; hra numeric; other numeric;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'b numeric; da numeric; hra numeric; other numeric;','cca numeric; hod numeric; b numeric; da numeric; hra numeric; other numeric;');
 if (length(src)-length(replace(src,'b=0;da=0;hra=0;other=0;','')))/length('b=0;da=0;hra=0;other=0;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'b=0;da=0;hra=0;other=0;','cca=0;hod=0;b=0;da=0;hra=0;other=0;');
 if (length(src)-length(replace(src,'other=other+sal.other*factor;','')))/length('other=other+sal.other*factor;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'other=other+sal.other*factor;','other=other+sal.other*factor;cca=cca+sal.cca*factor;hod=hod+sal.hod_allowance*factor;');
 if (length(src)-length(replace(src,'gross=b+da+hra+other;','')))/length('gross=b+da+hra+other;')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'gross=b+da+hra+other;','cca=round(cca,2);hod=round(hod,2);gross=b+da+hra+cca+other+hod;');
 if (length(src)-length(replace(src,'''HRA'',hra,''Other allowance'',other','')))/length('''HRA'',hra,''Other allowance'',other')<>1 then raise exception 'Salary function changed; review required';end if;
 src=replace(src,'''HRA'',hra,''Other allowance'',other','''HRA'',hra,''CCA'',cca,''Allowances'',other,''HOD/Coordinator Allowances'',hod');
 execute src;
end $patch$;
notify pgrst,'reload schema';
