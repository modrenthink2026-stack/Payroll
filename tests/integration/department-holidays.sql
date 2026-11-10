-- Synthetic fixtures only. Execute after the holiday migration. Always rolls back.
begin;
do $$
declare cid uuid=gen_random_uuid();other_cid uuid=gen_random_uuid();owner_id uuid;staff_user uuid=gen_random_uuid();teacher uuid=gen_random_uuid();office_staff uuid=gen_random_uuid();result jsonb;holiday_id uuid;revision int;denied boolean;before_hash text;after_hash text;period_hash text;plan jsonb;calculated_run uuid;
begin
 select m.user_id into owner_id from public.payroll_members m join auth.users u on u.id=m.user_id where m.role='admin' and u.email_confirmed_at is not null and not coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false) limit 1;
 if owner_id is null then raise exception 'Confirmed administrator required for rollback test';end if;
 insert into public.payroll_companies(id,name,settings,enabled_modules) values(cid,'Holiday synthetic QA rollback','{"department_holidays_enabled":true,"working_days":[1,2,3,4,5,6],"holidays":["2026-10-02"],"statutory_reviewed":true,"effective_from":"2026-01-01","pf_rate":12,"pf_employer_rate":12,"pf_cap":15000,"esi_rate":0.75,"esi_employer_rate":3.25,"deposit_enabled":false,"deposit_cap":0}','{"leave":true,"attendance":true,"payroll":true,"attendance_register_v1":true}'),(other_cid,'Holiday other QA rollback','{"working_days":[1,2,3,4,5,6],"holidays":[]}','{"leave":true}');
 insert into public.payroll_members(company_id,user_id,role) values(cid,owner_id,'admin');
 insert into auth.users(id,email,email_confirmed_at) values(staff_user,'holiday.qa.'||staff_user||'@example.invalid',now());
 insert into public.payroll_members(company_id,user_id,role) values(cid,staff_user,'staff');
 insert into public.payroll_staff(id,company_id,code,name,email,joining_date,department,user_id,shift_start,shift_end) values(teacher,cid,'HOL-T','Synthetic Teacher','teacher.'||teacher||'@example.invalid','2020-01-01','Teaching',staff_user,'08:00','14:30'),(office_staff,cid,'HOL-O','Synthetic Office','office.'||office_staff||'@example.invalid','2020-01-01','Office',null,'08:00','14:30');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 before_hash=payroll_private.fingerprint(cid);period_hash=payroll_private.attendance_period_hash(cid,'2026-10-01');
 result=public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','save','expected_revision',0,'name','Teaching holiday','from_date','2026-10-05','to_date','2026-10-05','scope','selected','departments',jsonb_build_array('Teaching')));
 select h.id,h.revision into holiday_id,revision from payroll_private.holiday_calendar h where h.company_id=cid and name='Teaching holiday';
 if payroll_private.working_day(cid,teacher,'2026-10-05') or not payroll_private.working_day(cid,office_staff,'2026-10-05') then raise exception 'Department scope failed';end if;
 if payroll_private.working_day(cid,teacher,'2026-10-02') or payroll_private.working_day(cid,office_staff,'2026-10-02') or payroll_private.working_day(cid,teacher,'2026-10-04') then raise exception 'Legacy common holiday / weekly off changed';end if;
 after_hash=payroll_private.fingerprint(cid);if before_hash=after_hash or period_hash=payroll_private.attendance_period_hash(cid,'2026-10-01') then raise exception 'Holiday edit did not invalidate payroll/period sources';end if;
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','cancel','id',holiday_id,'expected_revision',0));exception when others then denied=true;end;if not denied then raise exception 'Stale revision accepted';end if;
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','save','expected_revision',0,'name','Invalid department','from_date','2026-10-06','to_date','2026-10-07','scope','selected','departments',jsonb_build_array('Other company department')));exception when others then denied=true;end;if not denied then raise exception 'Unknown department accepted';end if;
 perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','save','expected_revision',0,'name','Common break','from_date','2026-10-06','to_date','2026-10-07','scope','all'));
 if payroll_private.working_day(cid,teacher,'2026-10-06') or payroll_private.working_day(cid,office_staff,'2026-10-07') then raise exception 'All-department range endpoints failed';end if;
 perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','save','expected_revision',0,'name','Office only','from_date','2026-10-08','to_date','2026-10-08','scope','selected','departments',jsonb_build_array('Office')));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',staff_user,'role','authenticated')::text,true);
 result=public.payroll_holidays(jsonb_build_object('company_id',cid));if jsonb_array_length(result->'items')<>2 then raise exception 'Staff saw another department holiday';end if;
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','cancel','id',holiday_id,'expected_revision',1));exception when others then denied=true;end;if not denied then raise exception 'Staff changed holiday calendar';end if;
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',other_cid));exception when others then denied=true;end;if not denied then raise exception 'Other company exposed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 -- No real leaves are changed: synthetic approved leave must block calendar edits.
 insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid) values(cid,'CL',12,true);
 insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,half_day,units,reason,status,created_by) values(cid,teacher,'CL','2026-10-05','2026-10-05',false,1,'Synthetic test leave','approved',owner_id);
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','cancel','id',holiday_id,'expected_revision',1));exception when others then denied=true;end;if not denied then raise exception 'Approved leave was silently recalculated';end if;
 delete from public.payroll_leaves where company_id=cid;
 insert into payroll_private.attendance_periods(company_id,month,status) values(cid,'2026-10-01','finalized');
 denied=false;begin perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','cancel','id',holiday_id,'expected_revision',1));exception when others then denied=true;end;if not denied then raise exception 'Confirmed month holiday was changed';end if;
 delete from payroll_private.attendance_periods where company_id=cid;
 -- Late calculations exclude this holiday for Teaching, retain it for Office.
 insert into public.payroll_attendance(company_id,staff_id,work_date,status,in_time,late_minutes,raw_late_minutes,reviewed_by) values(cid,teacher,'2026-10-05','present','08:30',30,30,owner_id),(cid,office_staff,'2026-10-05','present','08:30',30,30,owner_id);
 if (payroll_private.late_plan(teacher,'2026-10-01')->>'total_seconds')::int<>0 or (payroll_private.late_plan(office_staff,'2026-10-01')->>'total_seconds')::int<>1800 then raise exception 'Department holiday late exemption failed';end if;
 if (select count(*) from generate_series('2026-10-05'::date,'2026-10-08'::date,'1 day') work_date where payroll_private.working_day(cid,teacher,work_date::date))<>1 then raise exception 'Department leave working-day count failed';end if;
 -- Salary calculation pays the department holiday, while an Office absence remains LOP.
 insert into public.payroll_profiles(company_id,staff_id) values(cid,teacher),(cid,office_staff);
 insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,approved_by) values(cid,teacher,'2026-10-01',31000,owner_id),(cid,office_staff,'2026-10-01',31000,owner_id);
 insert into public.payroll_attendance(company_id,staff_id,work_date,status,late_minutes,early_minutes,raw_late_minutes,reviewed_by)
 select cid,st.id,cal::date,'present',0,0,0,owner_id from public.payroll_staff st cross join generate_series('2026-10-01'::date,'2026-10-31'::date,'1 day') cal where st.company_id=cid
 on conflict(staff_id,work_date) do update set status='present',late_minutes=0,raw_late_minutes=0;
 update public.payroll_attendance set status='absent' where company_id=cid and work_date='2026-10-05';
 calculated_run=payroll_private.calculate(cid,'2026-10-01');
 if (select gross from public.payroll_lines where run_id=calculated_run and staff_id=teacher) is distinct from 31000::numeric then raise exception 'Teaching holiday was deducted from salary';end if;
 if (select gross from public.payroll_lines where run_id=calculated_run and staff_id=office_staff) is distinct from 30000::numeric then raise exception 'Office absence was incorrectly paid as a department holiday';end if;
 perform public.payroll_holidays(jsonb_build_object('company_id',cid,'mode','cancel','id',holiday_id,'expected_revision',1));
 if not payroll_private.working_day(cid,teacher,'2026-10-05') or not exists(select 1 from payroll_private.holiday_events where company_id=cid and action='cancel') then raise exception 'Reversible cancellation / history failed';end if;
end$$;
rollback;
