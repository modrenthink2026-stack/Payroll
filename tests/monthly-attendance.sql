begin;
do $$
declare owner_id uuid; cid uuid=gen_random_uuid(); othercid uuid=gen_random_uuid(); hr_id uuid=gen_random_uuid();
 sid uuid=gen_random_uuid(); sid2 uuid=gen_random_uuid(); outsider uuid=gen_random_uuid(); q jsonb; p jsonb; fresh jsonb; j jsonb; result jsonb; caught boolean; msg text; n int; before_rows jsonb;
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(hr_id,'monthly-hr@example.invalid',now());
 insert into public.payroll_companies(id,name) values(cid,'Synthetic monthly attendance'),(othercid,'Other monthly company');
 insert into public.payroll_members values(cid,owner_id,'admin'),(cid,hr_id,'hr');
 insert into public.payroll_staff(id,company_id,code,name,department,joining_date,shift_start,shift_end,early_grace) values
 (sid,cid,'M1','Synthetic monthly teacher','Teaching','2026-01-01','07:56','14:20',3),
 (sid2,cid,'M2','Synthetic monthly office','Office','2026-01-01','09:00','18:00',0),
 (outsider,othercid,'MX','Synthetic other employee','Office','2026-01-01','09:00','18:00',0);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 j=jsonb_build_array(jsonb_build_object('staff_id',sid,'work_date','2026-10-01'),jsonb_build_object('staff_id',sid,'work_date','2026-10-02'),jsonb_build_object('staff_id',sid2,'work_date','2026-10-31'));
 q=public.payroll_monthly_attendance(jsonb_build_object('mode','load','company_id',cid,'month','2026-10-01','rows',j));
 if jsonb_array_length(q)<>3 or (q->0->'staff'->>'early_grace')::int<>3 or q->0->'attendance'<>'null'::jsonb then raise exception 'Monthly all-department snapshot failed';end if;
 select jsonb_agg(x||jsonb_build_object('status','present','in_time','09:05:23','out_time','14:17:31','late_minutes',5,'early_minutes',2,'note','Monthly source review','calculate_shift',false)) into j from jsonb_array_elements(q) x;
 p=jsonb_build_object('mode','save','company_id',cid,'month','2026-10-01','rows',j,'reason','Reviewed all departments for the month','request_id',gen_random_uuid());
 result=public.payroll_monthly_attendance(p);
 if (result->>'updated')::int<>3 or (select count(*) from public.payroll_attendance where company_id=cid)<>3 or not exists(select 1 from public.payroll_attendance where staff_id=sid and work_date='2026-10-02' and in_time='09:05:23' and raw_late_minutes=5) then raise exception 'Monthly multi-date/multi-department save failed';end if;
 select count(*) into n from public.payroll_audit where company_id=cid;
 perform public.payroll_monthly_attendance(p);
 if (select count(*) from public.payroll_audit where company_id=cid)<>n then raise exception 'Monthly retry repeated writes';end if;
 caught=false;begin perform public.payroll_monthly_attendance(p||'{"reason":"Different retry body"}');exception when others then caught=true;end;
 if not caught then raise exception 'Reused request ID accepted changed data';end if;
 caught=false;begin perform public.payroll_monthly_attendance(p||jsonb_build_object('request_id',gen_random_uuid()));exception when others then caught=true;end;
 if not caught then raise exception 'Stale monthly snapshot accepted';end if;
 q=public.payroll_monthly_attendance(p||jsonb_build_object('mode','load'));
 select jsonb_agg(x||jsonb_build_object('status','present','in_time','09:06:00','out_time','14:18:00','late_minutes',6,'early_minutes',1)) into j from jsonb_array_elements(q) x;
 fresh=p||jsonb_build_object('rows',j,'request_id',gen_random_uuid());
 select jsonb_agg(to_jsonb(a) order by a.staff_id,a.work_date) into before_rows from public.payroll_attendance a where company_id=cid;
 -- A later department fails after earlier groups have executed: the whole month rolls back.
 insert into public.payroll_late_reviews(company_id,staff_id,month,source_hash,plan,decisions,cl_units,reason,reviewed_by) values(cid,sid2,'2026-10-01','synthetic','{}','[]',0,'Existing completed review',owner_id);
 caught=false;msg='';begin perform public.payroll_monthly_attendance(fresh);exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('Reopen' in msg)=0 or (select jsonb_agg(to_jsonb(a) order by a.staff_id,a.work_date) from public.payroll_attendance a where company_id=cid) is distinct from before_rows then raise exception 'Monthly review guard or atomic rollback failed: %',msg;end if;
 update public.payroll_late_reviews set status='reopened' where company_id=cid;
 insert into public.payroll_runs(company_id,month,status,input_hash,snapshot) values(cid,'2026-10-01','locked','synthetic','{}');
 caught=false;msg='';begin perform public.payroll_monthly_attendance(fresh);exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('locked' in msg)=0 then raise exception 'Monthly import changed locked payroll';end if;
 update public.payroll_runs set status='calculated' where company_id=cid;
 update public.payroll_staff set early_grace=4 where id=sid;
 caught=false;begin perform public.payroll_monthly_attendance(fresh);exception when others then caught=true;end;
 if not caught then raise exception 'Monthly stale grace accepted';end if;
 update public.payroll_staff set early_grace=3 where id=sid;
 for j in select * from jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||jsonb_build_object('staff_id',outsider))),
  jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"work_date":"2026-11-01"}')),
  jsonb_build_object('rows',jsonb_build_array(fresh->'rows'->0,fresh->'rows'->0)),
  jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"status":""}')),
  jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"late_minutes":-1}')),
  jsonb_build_object('month','2026-10-02'),jsonb_build_object('rows','[]'::jsonb)
 )) loop
  caught=false;begin perform public.payroll_monthly_attendance(fresh||j||jsonb_build_object('request_id',gen_random_uuid()));exception when others then caught=true;end;
  if not caught then raise exception 'Invalid monthly data accepted: %',j;end if;
 end loop;
 update public.payroll_members set role='accountant' where company_id=cid and user_id=hr_id;
 caught=false;begin perform public.payroll_monthly_attendance(fresh);exception when others then caught=true;end;if not caught then raise exception 'Accountant monthly write allowed';end if;
 caught=false;begin perform public.payroll_monthly_attendance(fresh||'{"mode":"load"}');exception when others then caught=true;end;if not caught then raise exception 'Accountant monthly preview allowed';end if;
 update public.payroll_members set role='hr' where company_id=cid and user_id=hr_id;
 update public.payroll_companies set enabled_modules=enabled_modules||'{"attendance":false}' where id=cid;
 caught=false;begin perform payroll_private.monthly_attendance(fresh);exception when others then caught=true;end;if not caught then raise exception 'Private monthly endpoint bypasses module pause';end if;
 update public.payroll_companies set enabled_modules=enabled_modules||'{"attendance":true}' where id=cid;
 update auth.users set raw_app_meta_data='{"payroll_password_change_required":true}' where id=hr_id;
 caught=false;begin perform public.payroll_monthly_attendance(fresh);exception when others then caught=true;end;if not caught then raise exception 'Temporary password bypass';end if;
 update auth.users set raw_app_meta_data='{}' where id=hr_id;
 -- The monthly endpoint can exceed the old 1,000-row report limit.
 insert into public.payroll_staff(company_id,code,name,department,joining_date) select cid,'LARGE-'||i,'Synthetic large month '||i,case when i%2=0 then 'Office' else 'Teaching' end,'2026-01-01' from generate_series(1,33) i;
 select jsonb_agg(jsonb_build_object('staff_id',s.id,'work_date',d::date)) into j from public.payroll_staff s cross join generate_series('2026-10-01'::date,'2026-10-31'::date,'1 day') d where s.company_id=cid and s.code like 'LARGE-%';
 q=public.payroll_monthly_attendance(jsonb_build_object('mode','load','company_id',cid,'month','2026-10-01','rows',j));
 if jsonb_array_length(q)<>1023 then raise exception 'Whole-month load above 1,000 rows failed';end if;
 select jsonb_agg(x||jsonb_build_object('status','absent','late_minutes',0,'early_minutes',0)) into j from jsonb_array_elements(q) x;
 result=public.payroll_monthly_attendance(jsonb_build_object('mode','save','company_id',cid,'month','2026-10-01','rows',j,'reason','Synthetic full-month scale check','request_id',gen_random_uuid()));
 if (result->>'updated')::int<>1023 then raise exception 'Whole-month save above 1,000 rows failed';end if;
 if exists(select 1 from public.payroll_attendance where company_id=othercid) then raise exception 'Other company attendance changed';end if;
end$$;
rollback;
select 'PASS: monthly all-department load/save, >1000 rows, atomic rollback, retries, snapshots, permissions, module pause, password, payroll locks and late-review guards' result;
