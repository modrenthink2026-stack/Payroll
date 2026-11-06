-- Synthetic fixtures only. All records are rolled back.
begin;
do $$
declare cid uuid=gen_random_uuid();sid uuid=gen_random_uuid();legacy uuid=gen_random_uuid();owner_id uuid;d int;seconds int;plan jsonb;old_hash text;new_hash text;
begin
 insert into public.payroll_companies(id,name,settings) values(cid,'Raw biometric QA rollback','{"working_days":[1,2,3,4,5,6,7],"holidays":[]}');
 insert into public.payroll_staff(id,company_id,code,name,email,joining_date,shift_start,shift_end) values(sid,cid,'RAW-QA','Synthetic Employee','qa.raw@example.invalid','2020-01-01','07:55','14:30'),(legacy,cid,'LEG-QA','Legacy Employee','qa.legacy@example.invalid','2020-01-01','07:55','14:30');
 for d,seconds in select * from (values(18,81),(19,171),(22,196),(16,400),(26,611),(28,649),(23,921),(24,944)) v(d,seconds) loop
  insert into public.payroll_attendance(company_id,staff_id,work_date,status,in_time,out_time,raw_late_minutes,late_minutes,shift_snapshot) values(cid,sid,make_date(2026,9,d),'present',('07:55'::time+make_interval(secs=>seconds))::time,'14:30',seconds/60,seconds/60,jsonb_build_object('start','07:55:00','end','14:30:00','raw_late_seconds',seconds));
 end loop;
 plan=payroll_private.late_plan(sid,'2026-09-01');
 if (plan->>'total_seconds')::int<>3973 or (plan->>'used_seconds')::int<>1459 or (plan->>'unused_seconds')::int<>41 then raise exception 'Exact second totals failed: %',plan;end if;
 if (select count(*) from jsonb_array_elements(plan->'events') e where not (e->>'covered')::boolean)<>3 then raise exception 'Expected three proposed half-day decisions';end if;
 if (plan->'events'->4->>'cumulative_seconds')::int<>1459 or (plan->'events'->5->>'cumulative_seconds')::int<>2108 then raise exception 'Sorted cumulative totals failed';end if;
 insert into public.payroll_attendance(company_id,staff_id,work_date,status,in_time,out_time,raw_late_minutes,late_minutes) values(cid,legacy,'2026-09-01','present','08:20','14:30',25,25);
 plan=payroll_private.late_plan(legacy,'2026-09-01');if (plan->>'total_seconds')::int<>1500 or not (plan->'events'->0->>'covered')::boolean then raise exception 'Legacy minute boundary changed';end if;
 -- The hash is still the established attendance/leave hash; changing function code alone must not invalidate reviews.
 select md5(jsonb_build_array('2026-09-01'::date,25,s.id,s.joining_date,s.leaving_date,c.settings->'working_days',c.settings->'holidays',
  (select jsonb_agg(to_jsonb(a) order by a.work_date,a.id) from public.payroll_attendance a where a.staff_id=s.id and a.work_date>='2026-09-01' and a.work_date<'2026-10-01'),
  (select jsonb_agg(jsonb_build_array(l.id,l.from_date,l.to_date,l.half_day,l.leave_type) order by l.id) from public.payroll_leaves l where l.staff_id=s.id and l.status='approved' and l.to_date>='2026-09-01' and l.from_date<'2026-10-01'))::text) into old_hash
 from public.payroll_staff s join public.payroll_companies c on c.id=s.company_id where s.id=legacy;
 if plan->>'source_hash'<>old_hash then raise exception 'Legacy review hash changed';end if;
 if has_function_privilege('anon','public.payroll_raw_biometric(jsonb)','execute') then raise exception 'Anonymous raw import exposed';end if;
end$$;
rollback;
