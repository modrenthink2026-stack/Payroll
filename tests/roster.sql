-- Proposed rollback checks; execute only after the roster upgrade is approved/applied.
begin;
do $$
declare uid uuid; cid uuid; sid uuid; other_user uuid=gen_random_uuid(); p jsonb; j jsonb; denied boolean;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA roster rollback"}')->>'id')::uuid;
 j=jsonb_build_object('code','ROSTER-QA','name','Synthetic Staff','joining_date','2026-10-01','department','QA','designation','Tester','personal_details','{"Staff Code":"ROSTER-QA","Staff Name":"Synthetic Staff","Email":"contact@example.invalid","UserType Name":"Administrator","AccessLevel":"Full","Security Deposit":"1000"}'::jsonb,'source_records','[{"S NO":"1","Security Deposit":"1000"},{"S NO":"2","Security Deposit":"2000"}]'::jsonb);
 p=jsonb_build_object('company_id',cid,'request_id',gen_random_uuid(),'rows',jsonb_build_array(j));
 perform public.payroll_api('staff_roster_import',p);perform public.payroll_api('staff_roster_import',p);
 select id into sid from public.payroll_staff where company_id=cid and code='ROSTER-QA';
 if (select count(*) from public.payroll_staff where company_id=cid)<>1 then raise exception 'Replay duplicated staff';end if;
 if exists(select 1 from public.payroll_staff where id=sid and (email is not null or user_id is not null)) then raise exception 'Contact email created login binding';end if;
 if exists(select 1 from public.payroll_salaries where staff_id=sid) or exists(select 1 from public.payroll_deposits where staff_id=sid) then raise exception 'Salary or ledger invented';end if;
 if (select jsonb_array_length(source_records) from public.payroll_staff_details where staff_id=sid)<>2 then raise exception 'Source rows lost';end if;
 denied=false;begin perform public.payroll_api('staff_roster_import',jsonb_build_object('company_id',cid,'rows',jsonb_build_array(j||'{"code":"NEW"}',j)));exception when others then denied=true;end;
 if not denied or exists(select 1 from public.payroll_staff where company_id=cid and code='NEW') then raise exception 'Partial import or overwrite';end if;
 insert into auth.users(id,email,email_confirmed_at) values(other_user,'qa-roster-accountant@example.invalid',now());
 insert into public.payroll_members values(cid,other_user,'accountant');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
 if (public.payroll_api('state',jsonb_build_object('company_id',cid))->'staff_details')<>'[]'::jsonb then raise exception 'Personnel details exposed to accountant';end if;
 denied=false;begin perform public.payroll_api('staff_roster_import',p-'request_id');exception when others then denied=true;end;
 if not denied then raise exception 'Accountant import permitted';end if;
end$$;
set local role authenticated;
select case when count(*)=0 then 'PASS: personnel RLS hides synthetic HR-only details' else 'FAIL' end as rls_result from public.payroll_staff_details where details->>'Staff Code'='ROSTER-QA';
reset role;
rollback;
