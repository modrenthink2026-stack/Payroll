begin;
do $$
declare uid uuid; cid uuid; sid uuid; rid uuid; j jsonb; cases jsonb='[]'; expected jsonb; lop_staff uuid; caught boolean;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Automatic PT QA rollback"}')->>'id')::uuid;
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true,"pt_auto_slabs":true,"pt_effective_from":"2026-10-01"}' where id=cid;
 for j in select * from jsonb_array_elements('[{"amount":15000,"expected":0,"mode":"component"},{"amount":15000.01,"expected":150,"mode":"component"},{"amount":20000,"expected":150,"mode":"component"},{"amount":20000.01,"expected":200,"mode":"component"},{"amount":15000,"expected":0,"mode":"consolidated"},{"amount":18000,"expected":150,"mode":"consolidated"},{"amount":25000,"expected":200,"mode":"consolidated"},{"amount":25000,"expected":0,"mode":"consolidated","pt_override":0}]') loop
  sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','PT-'||jsonb_array_length(cases),'name','PT boundary QA','email','','joining_date','2026-10-01','salary_mode',j->>'mode','consolidated_amount',j->'amount','basic',j->'amount','da',0,'hra',0,'other',0,'pt_override',j->'pt_override'))->>'id')::uuid;
  update public.payroll_profiles set pt=999 where staff_id=sid;
  perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present'));
  cases=cases||jsonb_build_array(jsonb_build_object('staff_id',sid,'expected',j->'expected'));
  if j->>'mode'='component' and (j->>'amount')::numeric>20000 then lop_staff=sid;end if;
 end loop;
 sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','PT-HOD','name','HOD PT QA','email','','joining_date','2026-10-01','basic',14000,'da',0,'hra',0,'other',0,'hod_allowance',2000))->>'id')::uuid;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present'));
 cases=cases||jsonb_build_array(jsonb_build_object('staff_id',sid,'expected',150));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 for expected in select * from jsonb_array_elements(cases) loop
  if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=(expected->>'staff_id')::uuid and (deductions->>'PT')::numeric=(expected->>'expected')::numeric) then raise exception 'Automatic PT boundary, mode or override failed';end if;
 end loop;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',lop_staff,'from_date','2026-10-01','to_date','2026-10-15','status','absent'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=lop_staff and gross<15000 and (deductions->>'PT')::numeric=0) then raise exception 'PT did not use earned monthly gross';end if;
 update public.payroll_companies set settings=settings||'{"pt_effective_from":"2026-11-01"}' where id=cid;
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=lop_staff and (deductions->>'PT')::numeric=999) then raise exception 'Pre-policy default changed';end if;
 update public.payroll_companies set settings=settings||'{"pt_auto_slabs":false,"pt_effective_from":"2026-10-01"}' where id=cid;
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=lop_staff and (deductions->>'PT')::numeric=999) then raise exception 'Manual PT mode changed';end if;
 caught=false;begin perform public.payroll_api('settings',jsonb_build_object('company_id',cid,'name','Invalid PT month QA','settings',(select settings from public.payroll_companies where id=cid)||'{"pt_auto_slabs":true,"pt_effective_from":"2026-10-02"}'));exception when others then caught=true;end;
 if not caught then raise exception 'Invalid PT policy month accepted';end if;
end$$;
rollback;
select 'PASS: automatic PT for both modes, exact boundaries and paise, HOD inclusion, explicit zero, earned gross after LOP, policy date/manual defaults and settings validation' as result;
