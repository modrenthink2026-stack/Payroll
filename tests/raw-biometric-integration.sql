-- Live-schema integration with synthetic company/staff only; ALWAYS rolls back.
begin;
do $$
declare cid uuid=gen_random_uuid();other_cid uuid=gen_random_uuid();sid uuid=gen_random_uuid();owner_id uuid;accountant_id uuid=gen_random_uuid();
 initial jsonb;body jsonb;response jsonb;saved jsonb;plan jsonb;events jsonb='[]';d int;sec int;denied boolean;req uuid;
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
