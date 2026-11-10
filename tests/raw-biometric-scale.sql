begin;
set local statement_timeout='60s';
do $$
declare cid uuid=gen_random_uuid();owner_id uuid;initial jsonb;events jsonb;response jsonb;started timestamptz;
begin
 select m.user_id into owner_id from payroll_members m join auth.users u on u.id=m.user_id where m.role='admin' and u.email_confirmed_at is not null and not coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false) limit 1;
 insert into payroll_companies(id,name,settings,enabled_modules) values(cid,'October scale QA rollback','{"working_days":[1,2,3,4,5,6,7],"holidays":[]}','{"attendance":true,"attendance_register_v1":true}');
 insert into payroll_members(company_id,user_id,role) values(cid,owner_id,'admin');
 insert into payroll_staff(company_id,code,name,email,joining_date,department,shift_start,shift_end,biometric_id)
 select cid,'SCALE-'||i,'Synthetic Scale '||i,'qa.'||cid||'.'||i||'@example.invalid','2020-01-01','QA','08:00','14:30','QA-'||i from generate_series(1,246) i;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 initial=public.payroll_raw_biometric(jsonb_build_object('company_id',cid,'month','2026-10-01','mode','load'));
 select jsonb_agg(jsonb_build_object('biometric_id',s.biometric_id,'name',s.name,'work_date',make_date(2026,10,d),'log_time',p.t,'direction',p.dir,'manual_entry',false)) into events
 from payroll_staff s cross join generate_series(1,22) d cross join(values('08:01:21','in'),('14:30:00','out')) p(t,dir) where company_id=cid;
 started=clock_timestamp();
 response=public.payroll_raw_biometric(jsonb_build_object('company_id',cid,'month','2026-10-01','mode','import','source_hash',initial->>'source_hash','rows',events,'reason','Full-size synthetic October import','request_id',gen_random_uuid()));
 if (select count(*) from payroll_punches where company_id=cid)<>10824 then raise exception 'Monthly scale punch count differs';end if;
 if clock_timestamp()-started > interval '50 seconds' then raise exception 'Full-size monthly import exceeds API budget: %',clock_timestamp()-started;end if;
end$$;
rollback;
