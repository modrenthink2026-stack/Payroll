begin;
do $$
declare uid uuid;cid uuid;sid uuid;rid uuid;j jsonb;ic uuid;reviewer uuid=gen_random_uuid();caught boolean;n numeric;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(reviewer,'qa-boundary@example.invalid',now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA edge cases"}')->>'id')::uuid;
 insert into public.payroll_members values(cid,reviewer,'accountant');
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true,"effective_from":"2026-01-01"}' where id=cid;
 sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','EDGE1','name','Boundary Staff','email','boundary@example.invalid','joining_date','2026-02-15','basic',28000,'da',0,'hra',0,'other',0))->>'id')::uuid;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-02-15','to_date','2026-02-28','status','present'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-02-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=14000 and paid_days=14) then raise exception 'February joining proration failed';end if;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-03-01','to_date','2026-03-31','status','present'));
 -- March has one tax month remaining; retain cents from component proration.
 perform public.payroll_api('tax_inputs',jsonb_build_object('company_id',cid,'staff_id',sid,'annual_tax',1200,'tax_paid',200,'other_deductions',0,'pt',0));
 ic=(public.payroll_api('increment_save',jsonb_build_object('company_id',cid,'staff_id',sid,'effective_from','2026-03-16','basic',31000,'da',0,'hra',0,'other',0,'reason','Mid-month approved test'))->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',ic,'decision','accountant_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',ic,'decision','approved'));
 caught=false;begin perform public.payroll_api('increment_decide',jsonb_build_object('company_id',cid,'id',ic,'decision','approved'));exception when others then caught=true;end;
 if not caught or (select count(*) from public.payroll_salaries where staff_id=sid and effective_from='2026-03-16')<>1 then raise exception 'Increment applied twice';end if;
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-03-01'))->>'id')::uuid;
 n=round((28000::numeric*15+31000::numeric*16)/31,2);
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=n and (deductions->>'TDS')::numeric=1000) then raise exception 'Mid-month salary/TDS month boundary failed';end if;
 -- High deductions are visible exceptions and cannot be approved.
 perform public.payroll_api('tax_inputs',jsonb_build_object('company_id',cid,'staff_id',sid,'annual_tax',100000,'tax_paid',0,'other_deductions',0,'pt',0));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-03-01'))->>'id')::uuid;
 caught=false;begin perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','hr_reviewed'));exception when others then caught=true;end;
 if not caught then raise exception 'Negative-pay payroll authorized';end if;
 -- Unknown or duplicate biometric imports.
 update public.payroll_staff set biometric_id='EDGE1' where id=sid;
 j=jsonb_build_object('company_id',cid,'rows',jsonb_build_array(jsonb_build_object('biometric_id','EDGE1','device_id','QA','event_id','001','event_timestamp_iso8601','2026-03-02T09:00:00+05:30','punch_direction','in')));
 perform public.payroll_api('punch_import',j);perform public.payroll_api('punch_import',j);
 if (select count(*) from public.payroll_punches where company_id=cid)<>1 then raise exception 'Duplicate punch imported';end if;
 caught=false;begin perform public.payroll_api('punch_import',j||jsonb_build_object('rows',jsonb_build_array(jsonb_build_object('biometric_id','unknown','device_id','QA','event_id','002','event_timestamp_iso8601','2026-03-02T09:00:00+05:30','punch_direction','in'))));exception when others then caught=true;end;
 if not caught then raise exception 'Unknown device employee accepted';end if;
 raise notice 'PASS: February partial joining, mid-month increment, increment replay, March TDS, negative net gate, duplicate/unknown punches';
end$$;
rollback;
