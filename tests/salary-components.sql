begin;
do $$
declare uid uuid; reviewer uuid=gen_random_uuid(); cid uuid; sid uuid; rid uuid; inc uuid; caught boolean; p jsonb;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Salary components QA rollback"}')->>'id')::uuid;
 p=jsonb_build_object('company_id',cid,'code','SAL-QA','name','Salary QA','email','salary-qa@example.invalid','joining_date','2026-10-01','basic',20000,'da',2000,'hra',5000,'cca',1000,'other',1500,'hod_allowance',2500);
 sid=(public.payroll_api('staff_save',p)->>'id')::uuid;
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and cca=1000 and hod_allowance=2500 and gross=29500 and cum_gross=32000) then raise exception 'Salary components or generated totals missing';end if;
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true}' where id=cid;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=32000 and net=32000 and (earnings->>'CCA')::numeric=1000 and (earnings->>'HOD/Coordinator Allowances')::numeric=2500 and (select sum(value::numeric) from jsonb_each_text(earnings))=gross) then raise exception 'Payroll omissions or double counting';end if;
 insert into auth.users(id,email,email_confirmed_at) values(reviewer,'salary-reviewer@example.invalid',now());
 insert into public.payroll_members values(cid,reviewer,'accountant');
 inc=(public.payroll_api('increment_save',p||jsonb_build_object('staff_id',sid,'effective_from','2026-10-17','cca',2000,'hod_allowance',3500,'reason','Reviewed QA revision'))->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',inc,'decision','accountant_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',inc,'decision','approved'));
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and effective_from='2026-10-17' and cca=2000 and hod_allowance=3500 and cum_gross=34000) then raise exception 'Increment approval dropped components';end if;
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=32967.74 and (earnings->>'CCA')::numeric=1483.87 and (earnings->>'HOD/Coordinator Allowances')::numeric=2983.87) then raise exception 'Split-period proration failed';end if;
 -- Initial salary and CSV import must retain the same components.
 insert into public.payroll_staff(company_id,code,name,email,joining_date) values(cid,'SAL-INITIAL','Initial QA','salary-initial@example.invalid','2026-10-01') returning id into sid;
 perform public.payroll_api('initial_salary',p||jsonb_build_object('staff_id',sid,'effective_from','2026-10-01'));
 if not exists(select 1 from public.payroll_salaries where staff_id=sid and cca=1000 and hod_allowance=2500) then raise exception 'Initial salary dropped components';end if;
 perform public.payroll_api('staff_import',jsonb_build_object('company_id',cid,'rows',jsonb_build_array(p||'{"code":"SAL-CSV","email":"salary-csv@example.invalid"}')));
 if not exists(select 1 from public.payroll_salaries v join public.payroll_staff s on s.id=v.staff_id where s.company_id=cid and s.code='SAL-CSV' and v.cca=1000 and v.hod_allowance=2500) then raise exception 'CSV dropped components';end if;
 caught=false;begin perform public.payroll_api('staff_save',p||'{"code":"NEG","email":"salary-neg@example.invalid","cca":-1}');exception when check_violation then caught=true;end;
 if not caught then raise exception 'Negative component accepted';end if;
end$$;
rollback;
select 'PASS: component persistence, computed totals, payroll inclusion, no double count, approval propagation, split-period proration and negative rejection' as result;
