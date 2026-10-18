begin;
do $$
declare uid uuid; cid uuid; sid uuid; rid uuid; version uuid; reviewer uuid=gen_random_uuid(); rec uuid; p jsonb;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Consolidated QA rollback"}')->>'id')::uuid;
 p=jsonb_build_object('company_id',cid,'code','CON-QA','name','Consolidated QA','email','','joining_date','2026-10-01','salary_mode','consolidated','consolidated_amount',18000,'pf_enabled',true,'esi_enabled',true);
 sid=(public.payroll_api('staff_save',p)->>'id')::uuid;
 select id into version from public.payroll_salaries where staff_id=sid;
 if not exists(select 1 from public.payroll_salaries where id=version and basic=0 and da=0 and hra=0 and cca=0 and hod_allowance=0 and consolidated_amount=18000 and gross=18000 and cum_gross=18000) then raise exception 'Consolidated version malformed';end if;
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true}' where id=cid;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and earnings='{"Consolidated salary":18000}'::jsonb and gross=18000 and net=18000 and deductions->>'PF'='0' and deductions->>'ESI'='0' and employer->>'PF total'='0' and employer->>'ESI'='0') then raise exception 'Consolidated pay charged PF/ESI or retained components';end if;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-01','status','absent'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=17419.35 and lop=1 and deductions->>'PF'='0' and deductions->>'ESI'='0') then raise exception 'Consolidated LOP proration failed';end if;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-01','status','present'));
 -- Switch to components partway through the month through the existing approval route.
 rec=(public.payroll_api('increment_save',jsonb_build_object('company_id',cid,'staff_id',sid,'effective_from','2026-10-17','reason','Reviewed mode change','salary_mode','component','basic',20000,'da',2000,'hra',5000,'cca',1000,'other',1500,'hod_allowance',2500))->>'id')::uuid;
 insert into auth.users(id,email,email_confirmed_at) values(reviewer,'con-reviewer@example.invalid',now());insert into public.payroll_members values(cid,reviewer,'accountant');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',rec,'decision','accountant_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',rec,'decision','approved'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and (earnings->>'Consolidated salary')::numeric=9290.32 and (deductions->>'PF')::numeric=1277 and (deductions->>'ESI')::numeric=80 and (select sum(value::numeric) from jsonb_each_text(earnings))=gross) then raise exception 'Mixed-mode contribution base or earnings failed';end if;
 -- Department entry accepts the single consolidated amount and preserves the selected mode.
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date) values(cid,'CON-DEP','Department consolidated',null,'Support','2026-10-01') returning id into sid;
 perform public.payroll_department_salaries(jsonb_build_object('company_id',cid,'department','Support','effective_from','2026-10-01','reason','Reviewed consolidated pay','request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'expected_salary_id',null,'salary_mode','consolidated','consolidated_amount',15000))));
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and salary_mode='consolidated' and consolidated_amount=15000) then raise exception 'Department entry lost consolidated mode';end if;
 rec=(public.payroll_api('increment_save',jsonb_build_object('company_id',cid,'staff_id',sid,'effective_from','2026-11-01','reason','Consolidated revision QA','salary_mode','consolidated','consolidated_amount',16000))->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',rec,'decision','accountant_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',rec,'decision','approved'));
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and effective_from='2026-11-01' and salary_mode='consolidated' and consolidated_amount=16000) then raise exception 'Consolidated approval lost salary mode';end if;
 perform public.payroll_api('staff_import',jsonb_build_object('company_id',cid,'rows',jsonb_build_array(p||'{"code":"CON-CSV","email":"con-csv@example.invalid"}')));
 if not exists(select 1 from public.payroll_salaries v join public.payroll_staff s on s.id=v.staff_id where s.company_id=cid and s.code='CON-CSV' and v.salary_mode='consolidated' and v.consolidated_amount=18000) then raise exception 'Consolidated CSV lost salary mode';end if;
 insert into public.payroll_staff(company_id,code,name,email,joining_date) values(cid,'CON-INITIAL','Consolidated initial',null,'2026-10-01') returning id into sid;
 perform public.payroll_api('initial_salary',jsonb_build_object('company_id',cid,'staff_id',sid,'effective_from','2026-10-01','salary_mode','consolidated','consolidated_amount',17000));
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and salary_mode='consolidated' and consolidated_amount=17000) then raise exception 'Initial consolidated entry failed';end if;

end$$;
rollback;
select 'PASS: consolidated storage and display, zero PF/ESI including employer, LOP proration, approved mode changes, mixed-month contribution base and department entry' as result;
