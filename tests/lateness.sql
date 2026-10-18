-- Rollback-only synthetic payroll checks. No real employee decisions are made.
begin;
do $$
declare owner_id uuid;worker uuid=gen_random_uuid();hr_id uuid=gen_random_uuid();outsider uuid=gen_random_uuid();cid uuid;othercid uuid;sid uuid;sid2 uuid;rid uuid; p jsonb;j jsonb;decs jsonb;payload jsonb;bad boolean;d date; i int; lid uuid;
 dates text[]=array['2026-10-01','2026-10-14','2026-10-02','2026-10-03','2026-10-05','2026-10-08','2026-10-15','2026-10-16','2026-10-17','2026-10-19','2026-10-20','2026-10-21','2026-10-23','2026-10-24','2026-10-22','2026-10-12','2026-10-09'];
 mins int[]=array[1,1,2,2,2,2,2,3,4,5,6,7,7,8,15,20,30];
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(worker,'qa-late-worker@example.invalid',now()),(hr_id,'qa-late-hr@example.invalid',now()),(outsider,'qa-late-outsider@example.invalid',now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA late policy rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"QA late second tenant rollback"}')->>'id')::uuid;
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true,"effective_from":"2026-10-01"}' where id=cid;
 sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','LATE-QA-1','name','Synthetic late employee','email','qa-late-worker@example.invalid','joining_date','2026-10-01','basic',31000,'da',0,'hra',0,'other',0,'shift_start','08:00','shift_end','14:30','late_grace',10))->>'id')::uuid;
 update public.payroll_staff set user_id=worker where id=sid;insert into public.payroll_members values(cid,worker,'staff'),(cid,hr_id,'manager'),(cid,outsider,'manager');
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present','in_time','07:58','out_time','14:30','calculate_shift',true));
 for i in 1..17 loop
  perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date',dates[i],'to_date',dates[i],'status','present','in_time',('08:00'::time+mins[i]*interval '1 minute')::text,'out_time','14:30','calculate_shift',true));
 end loop;
 p=payroll_private.late_plan(sid,'2026-10-01');
 if (p->>'total_minutes')::int<>117 or (p->>'used_minutes')::int<>24 or (p->>'unused_minutes')::int<>1 or jsonb_array_length(p->'events')<>17 then raise exception 'October cumulative example mismatch';end if;
 if (select count(*) from jsonb_array_elements(p->'events') e where not (e->>'covered')::boolean)<>7 then raise exception 'Strict 25-minute threshold should yield seven half-day reviews';end if;
 if not exists(select 1 from jsonb_array_elements(p->'events') e where e->>'date'='2026-10-20' and (e->>'cumulative_minutes')::int=30 and not (e->>'covered')::boolean and e->>'in_time'='08:06' and e->>'reporting_time'='08:00') then raise exception 'Boundary arrival not counted or In Time incorrect';end if;
 if exists(select 1 from jsonb_array_elements(p->'events') e where e->>'in_time'='07:58') then raise exception 'On-time/early In Time leaked into late report';end if;
 if (select raw_late_minutes from public.payroll_attendance where staff_id=sid and work_date='2026-10-09')<>30 or (select late_minutes from public.payroll_attendance where staff_id=sid and work_date='2026-10-09')<>20 then raise exception 'Daily grace double-counted against monthly allowance';end if;
 select jsonb_agg(jsonb_build_object('attendance_id',e->>'attendance_id','decision','lop')) into decs from jsonb_array_elements(p->'events') e where not (e->>'covered')::boolean;
 payload=jsonb_build_object('company_id',cid,'staff_id',sid,'month','2026-10-01','source_hash',p->>'source_hash','decisions',decs,'reason','Synthetic reviewed late decisions','request_id',gen_random_uuid());
 bad=false;begin perform public.payroll_api('late_review',payload);exception when others then bad=true;end;
 if not bad then raise exception 'Unassigned admin approved lateness';end if;
 -- The existing configured Principal/HR offices are the authority; no new salary role is needed.
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email','qa-late-worker@example.invalid'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 bad=false;begin perform public.payroll_api('late_review',payload);exception when others then bad=true;end;
 if not bad then raise exception 'Self-review permitted';end if;
 j=public.payroll_api('late_month',jsonb_build_object('company_id',cid,'month','2026-10-01'));
 if jsonb_array_length(j)<>1 then raise exception 'Own late report access failed';end if;
 bad=false;begin perform public.payroll_api('late_month',jsonb_build_object('company_id',othercid,'month','2026-10-01'));exception when others then bad=true;end;
 if not bad then raise exception 'Cross-company late report exposed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email',(select email from auth.users where id=owner_id)));
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','hr','email','qa-late-hr@example.invalid'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=sid and issues @> '["Principal / HR monthly late decision required"]') then raise exception 'Pending late decision did not block payroll review';end if;
 bad=false;begin perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','hr_reviewed'));exception when others then bad=true;end;
 if not bad then raise exception 'Unreviewed lateness approved for payroll';end if;
 bad=false;begin perform public.payroll_api('late_review',payload||'{"source_hash":"stale"}');exception when others then bad=true;end;
 if not bad then raise exception 'Stale report accepted';end if;
 perform public.payroll_api('late_review',payload);perform public.payroll_api('late_review',payload);
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=sid and lop=3.5 and paid_days=27.5 and gross=27500 and net=27500 and (late_summary->>'lop_days')::numeric=3.5 and jsonb_array_length(issues)=0) then raise exception 'Half-day LOP salary arithmetic failed';end if;
 -- Reviewed attendance cannot silently move an incident into/out of the allowance.
 bad=false;begin perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-20','to_date','2026-10-20','status','present','late_minutes',0));exception when others then bad=true;end;
 if not bad then raise exception 'Attendance changed under active review';end if;
 perform public.payroll_api('late_reopen',jsonb_build_object('company_id',cid,'staff_id',sid,'month','2026-10-01','reason','Switch synthetic decision to CL'));
 select jsonb_agg(jsonb_build_object('attendance_id',e->>'attendance_id','decision','cl')) into decs from jsonb_array_elements(p->'events') e where not (e->>'covered')::boolean;
 payload=payload||jsonb_build_object('decisions',decs,'request_id',gen_random_uuid());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 perform public.payroll_api('late_review',payload);perform public.payroll_api('late_review',payload);
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>8.5 then raise exception 'CL not debited exactly once';end if;
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if jsonb_array_length(j->'profiles')<>0 or jsonb_array_length(j->'salaries')<>0 or jsonb_array_length(j->'staff_details')<>0 then raise exception 'Late reviewer gained private payroll access';end if;
 -- Table RLS: an unrelated manager cannot read the review.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 execute 'set local role authenticated';if exists(select 1 from public.payroll_late_reviews where company_id=cid) then raise exception 'Late review direct RLS leaked';end if;execute 'reset role';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and staff_id=sid and lop=0 and gross=31000 and (late_summary->>'cl_days')::numeric=3.5 and jsonb_array_length(issues)=0) then raise exception 'CL incorrectly reduced salary';end if;
 perform public.payroll_api('late_reopen',jsonb_build_object('company_id',cid,'staff_id',sid,'month','2026-10-01','reason','Synthetic reopen refunds CL'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>12 then raise exception 'Reopen CL refund mismatch';end if;
 bad=false;begin perform public.payroll_api('late_reopen',jsonb_build_object('company_id',cid,'staff_id',sid,'month','2026-10-01','reason','Duplicate refund attempt'));exception when others then bad=true;end;
 if not bad or (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>12 then raise exception 'Duplicate CL refund permitted';end if;
 -- CL already reserved for submitted leave cannot fund lateness.
 insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,units,reason,created_by) values(cid,sid,'CL','2026-11-01','2026-11-12',12,'Synthetic reserved leave',worker) returning id into lid;
 bad=false;begin perform public.payroll_api('late_review',payload||jsonb_build_object('request_id',gen_random_uuid()));exception when others then bad=true;end;
 if not bad then raise exception 'Reserved CL consumed by late review';end if;
 delete from public.payroll_leaves where id=lid;
 -- Explicit source changes invalidate approval; locked payroll prevents reopening/refunds.
 select jsonb_agg(jsonb_build_object('attendance_id',e->>'attendance_id','decision','lop')) into decs from jsonb_array_elements(p->'events') e where not (e->>'covered')::boolean;
 perform public.payroll_api('late_review',payload||jsonb_build_object('decisions',decs,'request_id',gen_random_uuid()));
 update public.payroll_companies set settings=jsonb_set(settings,'{holidays}','["2026-10-20"]') where id=cid;
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and issues @> '["Late review inputs changed; reopen and review this month"]') then raise exception 'Changed policy silently retained late penalties';end if;
 update public.payroll_runs set status='locked' where id=rid;
 bad=false;begin perform public.payroll_api('late_reopen',jsonb_build_object('company_id',cid,'staff_id',sid,'month','2026-10-01','reason','Locked-month change'));exception when others then bad=true;end;
 if not bad then raise exception 'Locked payroll late review reopened';end if;
 -- The same employee receives a fresh allowance in a different calendar month.
 for i in 1..5 loop
  perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date',('2026-11-01'::date+i),'to_date',('2026-11-01'::date+i),'status','present','late_minutes',(array[0,2,30,10,3])[i]));
 end loop;
 j=payroll_private.late_plan(sid,'2026-11-01');
 if (j->>'total_minutes')::int<>45 or (j->>'used_minutes')::int<>15 or (select count(*) from jsonb_array_elements(j->'events') e where not (e->>'covered')::boolean)<>1 then raise exception 'Monthly allowance did not reset';end if;
 -- Already unpaid/half-day/leave/holiday dates must never incur another late penalty.
 insert into public.payroll_staff(company_id,code,name,email,joining_date,leaving_date) values(cid,'LATE-EXCLUDED','Synthetic exclusions',null,'2026-10-02','2026-10-30') returning id into sid2;
 insert into public.payroll_attendance(company_id,staff_id,work_date,status,late_minutes) values
 (cid,sid2,'2026-10-01','present',30),(cid,sid2,'2026-10-02','absent',30),(cid,sid2,'2026-10-03','half_day',30),
 (cid,sid2,'2026-10-04','present',30),(cid,sid2,'2026-10-05','present',30),(cid,sid2,'2026-10-20','present',30),(cid,sid2,'2026-10-31','present',30);
 insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,units,reason,status) values(cid,sid2,'CL','2026-10-05','2026-10-05',1,'Synthetic approved leave','approved');
 j=payroll_private.late_plan(sid2,'2026-10-01');if jsonb_array_length(j->'events')<>0 then raise exception 'Duplicate or out-of-employment late penalties generated';end if;

end$$;
select 'PASS: strict 25-minute October example, late-only In Time, authority/RLS, LOP/CL arithmetic, retries, refunds, reservations, stale inputs and payroll locks' as result;
rollback;
