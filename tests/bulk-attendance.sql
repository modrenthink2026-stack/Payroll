-- Synthetic rollback-only tests; no real attendance is edited.
begin;
do $$
declare owner_id uuid; cid uuid; othercid uuid; hr_id uuid=gen_random_uuid(); sid uuid; sid2 uuid; outsider uuid; q jsonb; p jsonb; fresh jsonb; j jsonb; result jsonb; caught boolean; msg text; n int;
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Department attendance QA rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"Other attendance tenant rollback"}')->>'id')::uuid;
 insert into auth.users(id,email,email_confirmed_at) values(hr_id,'qa-attendance-bulk-hr@example.invalid',now());insert into public.payroll_members values(cid,hr_id,'hr');
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date,shift_start,shift_end,late_grace) values(cid,'AT-1','Synthetic day',null,'Teaching','2026-10-01','08:00','14:30',10) returning id into sid;
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date,shift_start,shift_end) values(cid,'AT-2','Synthetic night',null,'Teaching','2026-10-01','22:00','06:00') returning id into sid2;
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date) values(othercid,'AT-X','Synthetic outsider',null,'Teaching','2026-10-01') returning id into outsider;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-11-02','to_date','2026-11-02','status','present','late_minutes',2));
 q=public.payroll_bulk_attendance(jsonb_build_object('mode','load','company_id',cid,'department','Teaching','work_date','2026-11-02'));
 if jsonb_array_length(q)<>2 or not exists(select 1 from jsonb_array_elements(q) x where x->>'staff_id'=sid2::text and x->'attendance'='null'::jsonb and x->'staff'->>'shift_start'='22:00:00') then raise exception 'Complete department/date load failed';end if;
 p=jsonb_build_object('mode','save','company_id',cid,'department','Teaching','work_date','2026-11-02','reason','Reviewed department times','request_id',gen_random_uuid(),'rows',jsonb_build_array(
 jsonb_build_object('staff_id',sid,'source_hash',(select x->>'source_hash' from jsonb_array_elements(q) x where x->>'staff_id'=sid::text),'status','present','in_time','08:03','out_time','14:30','late_minutes',0,'early_minutes',0,'calculate_shift',true,'out_next_day',false,'note','Day review'),
 jsonb_build_object('staff_id',sid2,'source_hash',(select x->>'source_hash' from jsonb_array_elements(q) x where x->>'staff_id'=sid2::text),'status','present','in_time','22:05','out_time','06:00','late_minutes',0,'early_minutes',0,'calculate_shift',true,'out_next_day',true,'note','Night review')));
 result=public.payroll_bulk_attendance(p);
 if (result->>'updated')::int<>2 or not exists(select 1 from public.payroll_attendance where staff_id=sid and work_date='2026-11-02' and raw_late_minutes=3 and late_minutes=0 and early_minutes=0) or not exists(select 1 from public.payroll_attendance where staff_id=sid2 and raw_late_minutes=5 and early_minutes=0 and (shift_snapshot->>'out_next_day')::boolean) then raise exception 'Bulk create/edit shift calculations failed';end if;
 select count(*) into n from public.payroll_audit where company_id=cid;
 perform public.payroll_bulk_attendance(p);
 if (select count(*) from public.payroll_audit where company_id=cid)<>n then raise exception 'Replay repeated attendance write';end if;
 caught=false;msg='';begin perform public.payroll_bulk_attendance(p||jsonb_build_object('request_id',gen_random_uuid()));exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('changed' in msg)=0 then raise exception 'Stale attendance edit accepted: %',msg;end if;
 q=public.payroll_bulk_attendance(jsonb_build_object('mode','load','company_id',cid,'department','Teaching','work_date','2026-11-02'));
 select jsonb_agg(x||jsonb_build_object('source_hash',(select z->>'source_hash' from jsonb_array_elements(q) z where z->>'staff_id'=x->>'staff_id'))) into j from jsonb_array_elements(p->'rows') x;
 fresh=p||jsonb_build_object('rows',j,'request_id',gen_random_uuid());
 -- A failure on the second row rolls back the already processed first row.
 insert into public.payroll_late_reviews(company_id,staff_id,month,source_hash,plan,decisions,cl_units,reason,reviewed_by) values(cid,sid2,'2026-11-01','synthetic','{}','[]',0,'Synthetic completed review',owner_id);
 caught=false;msg='';begin perform public.payroll_bulk_attendance(fresh||jsonb_build_object('rows',jsonb_set(fresh->'rows','{0,in_time}','"08:04"')));exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('Reopen' in msg)=0 or (select raw_late_minutes from public.payroll_attendance where staff_id=sid and work_date='2026-11-02')<>3 then raise exception 'Completed late-review guard or atomicity failed: %',msg;end if;
 update public.payroll_late_reviews set status='reopened' where company_id=cid;
 insert into public.payroll_runs(company_id,month,status,input_hash,snapshot) values(cid,'2026-11-01','locked','synthetic','{}');
 caught=false;msg='';begin perform public.payroll_bulk_attendance(fresh);exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('locked' in msg)=0 then raise exception 'Locked payroll edited: %',msg;end if;
 update public.payroll_runs set status='calculated' where company_id=cid;
 update public.payroll_staff set shift_start='08:01' where id=sid;
 caught=false;msg='';begin perform public.payroll_bulk_attendance(fresh);exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('changed' in msg)=0 then raise exception 'Stale shift snapshot accepted: %',msg;end if;
 update public.payroll_staff set shift_start='08:00' where id=sid;
 -- Cross-company rows, wrong department, duplicate rows and invalid minute values cannot write.
 for j in select * from jsonb_array_elements(jsonb_build_array(
 jsonb_build_object('department','Support'),
 jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||jsonb_build_object('staff_id',outsider))),
 jsonb_build_object('rows',jsonb_build_array(fresh->'rows'->0,fresh->'rows'->0)),
 jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"late_minutes":-1}')),
 jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"early_minutes":0.5}'))
 ,jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"status":""}'))
 ,jsonb_build_object('rows',jsonb_build_array((fresh->'rows'->0)||'{"status":"pending"}'))
 )) loop
  caught=false;begin perform public.payroll_bulk_attendance(fresh||j||jsonb_build_object('request_id',gen_random_uuid()));exception when others then caught=true;end;if not caught then raise exception 'Invalid department attendance accepted';end if;
 end loop;
 -- Saving one staff/date leaves the other staff record intact.
 perform public.payroll_bulk_attendance(fresh||jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array((fresh->'rows'->0)||'{"status":"absent","in_time":"","out_time":"","late_minutes":0,"calculate_shift":false}')));
 if not exists(select 1 from public.payroll_attendance where staff_id=sid and status='absent' and in_time is null and raw_late_minutes=0) or not exists(select 1 from public.payroll_attendance where staff_id=sid2 and status='present' and raw_late_minutes=5) then raise exception 'Selected row isolation failed';end if;
 update public.payroll_members set role='accountant' where company_id=cid and user_id=hr_id;
 caught=false;begin perform public.payroll_bulk_attendance(p);exception when others then caught=true;end;if not caught then raise exception 'Accountant edited attendance';end if;
 update public.payroll_members set role='staff' where company_id=cid and user_id=hr_id;
 caught=false;begin perform public.payroll_bulk_attendance(jsonb_build_object('mode','load','company_id',cid,'department','Teaching','work_date','2026-11-02'));exception when others then caught=true;end;if not caught then raise exception 'Staff accessed department attendance';end if;
 update public.payroll_members set role='hr' where company_id=cid and user_id=hr_id;
 update auth.users set raw_app_meta_data='{"payroll_password_change_required":true}' where id=hr_id;
 caught=false;begin perform public.payroll_bulk_attendance(p);exception when others then caught=true;end;if not caught then raise exception 'Temporary password bypass';end if;
end$$;
rollback;
select 'PASS: department attendance load/create/edit, selected/date scope, raw late and overnight shift calculation, stale attendance/shift, atomicity, idempotency, locked payroll, active late review, role/tenant/password gates' as result;
