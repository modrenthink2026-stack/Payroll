-- Live-schema integration with synthetic company/staff only; ALWAYS rolls back.
begin;
do $$
declare cid uuid=gen_random_uuid();other_cid uuid=gen_random_uuid();sid uuid=gen_random_uuid();owner_id uuid;accountant_id uuid=gen_random_uuid();
 initial jsonb;body jsonb;response jsonb;saved jsonb;plan jsonb;events jsonb='[]';d int;sec int;denied boolean;req uuid;expected_rows jsonb;
begin
 select m.user_id into owner_id from public.payroll_members m join auth.users u on u.id=m.user_id where m.role='admin' and u.email_confirmed_at is not null and not coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false) limit 1;
 if owner_id is null then raise exception 'A confirmed existing administrator is needed for rollback fixture';end if;
 insert into public.payroll_companies(id,name,settings,enabled_modules) values(cid,'Raw integration QA rollback','{"working_days":[1,2,3,4,5,6,7],"holidays":[]}','{"attendance":true,"attendance_register_v1":true}'),(other_cid,'Other raw QA rollback','{"working_days":[1,2,3,4,5,6,7],"holidays":[]}','{"attendance":true,"attendance_register_v1":true}');
 insert into public.payroll_members(company_id,user_id,role) values(cid,owner_id,'admin');
 insert into auth.users(id,email,email_confirmed_at) values(accountant_id,'qa.'||accountant_id::text||'@example.invalid',now());
 insert into public.payroll_members values(cid,accountant_id,'accountant');
 insert into public.payroll_staff(id,company_id,code,name,email,joining_date,department,shift_start,shift_end,biometric_id) values(sid,cid,'RAW-QA','Synthetic Raw Employee','qa.'||sid::text||'@example.invalid','2020-01-01','Teaching','07:55','14:30','QA-001');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 initial=public.payroll_raw_biometric(jsonb_build_object('company_id',cid,'month','2026-09-01','mode','load'));
 for d,sec in select * from(values(18,81),(19,171),(22,196),(16,400),(26,611),(28,649),(23,921),(24,944)) v(d,sec) loop
  events=events||jsonb_build_array(jsonb_build_object('biometric_id','QA-001','name','Synthetic Raw Employee','work_date',make_date(2026,9,d),'log_time',to_char(('07:55'::time+make_interval(secs=>sec))::time,'HH24:MI:SS'),'direction','in','manual_entry',false),jsonb_build_object('biometric_id','QA-001','name','Synthetic Raw Employee','work_date',make_date(2026,9,d),'log_time','14:30:00','direction','out','manual_entry',false));
 end loop;
 -- One missing OUT must remain pending, not become an automatic absence/present record.
 events=events||jsonb_build_array(jsonb_build_object('biometric_id','QA-001','name','Synthetic Raw Employee','work_date','2026-09-29','log_time','08:00:00','direction','in','manual_entry',false));
 body=jsonb_build_object('company_id',cid,'month','2026-09-01','mode','import','source_hash',initial->>'source_hash','rows',events,'reason','Synthetic import QA','request_id',gen_random_uuid());
 response=public.payroll_raw_biometric(body);
 if response is distinct from public.payroll_raw_biometric(body) then raise exception 'Import retry was not idempotent';end if;
 if (select count(*) from public.payroll_punches where company_id=cid)<>17 then raise exception 'Unexpected imported count';end if;
 denied=false;begin perform public.payroll_raw_biometric(body||jsonb_build_object('request_id',gen_random_uuid()));exception when others then denied=true;end;if not denied then raise exception 'Stale-source import accepted';end if;
 body=jsonb_build_object('company_id',cid,'month','2026-09-01','mode','save_normal','source_hash',response->>'source_hash','reason','Synthetic bulk HR review','request_id',gen_random_uuid());
 saved=public.payroll_raw_biometric(body);
 if (saved->>'updated')::int<>8 then raise exception 'Expected 8 ordinary reviewed days';end if;
 if saved is distinct from public.payroll_raw_biometric(body) then raise exception 'Bulk retry was not idempotent';end if;
 if exists(select 1 from public.payroll_attendance where company_id=cid and work_date='2026-09-29') then raise exception 'Missing OUT was silently approved';end if;
 expected_rows=(
 with raw as (
  select p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date work_date,
   jsonb_agg(jsonb_build_object('time',to_char(p.event_time at time zone 'Asia/Kolkata','HH24:MI:SS'),'direction',p.direction,'manual_entry',p.manual_entry) order by p.event_time,p.direction,p.id) punches
  from public.payroll_punches p where p.company_id=cid and p.event_time>='2026-09-01'::date::timestamp at time zone 'Asia/Kolkata'
   and p.event_time<('2026-09-01'::date+interval '1 month') at time zone 'Asia/Kolkata' group by p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date
 ),days as (
  select s.id staff_id,s.name,s.code,s.department,s.shift_start,s.shift_end,s.early_grace,calendar_day::date work_date,
   c.settings->'working_days' @> jsonb_build_array(extract(isodow from calendar_day)::int) and not c.settings->'holidays' @> jsonb_build_array(calendar_day::date::text) working_day,
   to_jsonb(a) attendance,coalesce(raw.punches,'[]'::jsonb) punches,
   (a.punch_hash is not distinct from payroll_private.day_punch_hash(cid,s.id,calendar_day::date) or (a.punch_hash is null and raw.punches is null))
    and (a.review_context_hash is null or a.review_context_hash=payroll_private.attendance_context_hash(cid,s.id)) evidence_current,
   (select jsonb_agg(jsonb_build_object('type',l.leave_type,'half_day',l.half_day,'paid',pol.paid)) from public.payroll_leaves l join public.payroll_leave_policies pol on pol.company_id=l.company_id and pol.code=l.leave_type where l.company_id=cid and l.staff_id=s.id and l.status='approved' and calendar_day::date between l.from_date and l.to_date) leaves,
   (select coalesce(sum(0.5),0) from public.payroll_late_reviews lr cross join jsonb_array_elements(lr.decisions) dec join public.payroll_attendance la on la.id=(dec->>'attendance_id')::uuid where lr.company_id=cid and lr.staff_id=s.id and lr.month='2026-09-01'::date and lr.status='active' and la.work_date=calendar_day::date and dec->>'decision'='lop') late_lop
  from public.payroll_staff s join public.payroll_companies c on c.id=s.company_id
  cross join lateral generate_series(greatest('2026-09-01'::date,s.joining_date),least(('2026-09-01'::date+interval '1 month - 1 day')::date,coalesce(s.leaving_date,'infinity'::date)),interval '1 day') calendar_day
  left join public.payroll_attendance a on a.company_id=cid and a.staff_id=s.id and a.work_date=calendar_day::date
  left join raw on raw.staff_id=s.id and raw.work_date=calendar_day::date
  where s.company_id=cid and s.joining_date<('2026-09-01'::date+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>='2026-09-01'::date
 ),review as (
  select *,coalesce(jsonb_array_length(leaves),0)>1 or
   (working_day and (leaves is null or (leaves->0->>'half_day')::boolean) and (attendance is null or attendance->>'reviewed_by' is null or not evidence_current)) or
   (jsonb_array_length(punches)>0 and attendance is not null and not evidence_current) unresolved
  from days
 ),units as (
  select *,case when not working_day then 1
   when leaves is not null and not (leaves->0->>'half_day')::boolean then case when (leaves->0->>'paid')::boolean then 1 else 0 end
   when leaves is not null then case when attendance->>'status'='absent' then case when (leaves->0->>'paid')::boolean then 0.5 else 0 end else case when (leaves->0->>'paid')::boolean then 1 else 0.5 end end
   when attendance->>'status'='absent' then 0 when attendance->>'status'='half_day' then 0.5 else 1 end units
  from review
 ) select coalesce(jsonb_agg(jsonb_build_object('staff_id',staff_id,'work_date',work_date,
  'staff',jsonb_build_object('name',name,'code',code,'department',department,'shift_start',shift_start,'shift_end',shift_end,'early_grace',early_grace),
  'working_day',working_day,'leave',leaves->0,'leave_count',coalesce(jsonb_array_length(leaves),0),
  'attendance',attendance,'punches',punches,'evidence_current',evidence_current,'unresolved',unresolved,
  'paid_days',case when unresolved then null else greatest(0,units-late_lop) end,
  'lop_days',case when unresolved then null else 1-greatest(0,units-late_lop) end
 ) order by work_date,department,name,staff_id),'[]'::jsonb) from units
);
 if expected_rows is distinct from saved->'rows' then raise exception 'Optimized register changed baseline attendance results';end if;
 plan=payroll_private.late_plan(sid,'2026-09-01');
 if (plan->>'total_seconds')::int<>3973 or (plan->>'used_seconds')::int<>1459 or (select count(*) from jsonb_array_elements(plan->'events') e where not(e->>'covered')::boolean)<>3 then raise exception 'Raw pipeline failed exact user example: %',plan;end if;
 if exists(select 1 from public.payroll_late_reviews where company_id=cid) or exists(select 1 from public.payroll_lines where company_id=cid) then raise exception 'Import auto-approved late deductions or payroll';end if;
 denied=false;begin perform public.payroll_raw_biometric(jsonb_build_object('company_id',other_cid,'month','2026-09-01','mode','load'));exception when others then denied=true;end;if not denied then raise exception 'Another company was exposed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',accountant_id,'role','authenticated')::text,true);
 response=public.payroll_raw_biometric(jsonb_build_object('company_id',cid,'month','2026-09-01','mode','load'));
 denied=false;begin perform public.payroll_raw_biometric(body||jsonb_build_object('request_id',gen_random_uuid(),'source_hash',response->>'source_hash'));exception when others then denied=true;end;if not denied then raise exception 'Accountant wrote attendance';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 update public.payroll_companies set enabled_modules=enabled_modules||'{"attendance":false}' where id=cid;
 denied=false;begin perform public.payroll_raw_biometric(jsonb_build_object('company_id',cid,'month','2026-09-01','mode','import','source_hash',response->>'source_hash','rows',events,'reason','Disabled module QA','request_id',gen_random_uuid()));exception when others then denied=true;end;if not denied then raise exception 'Disabled module accepted import';end if;
end$$;
rollback;
