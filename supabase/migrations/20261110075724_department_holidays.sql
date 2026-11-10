-- BEGIN CORE VERSION GUARD
do $guard$ begin
 if md5(pg_get_functiondef('payroll_private.dispatch(text,jsonb)'::regprocedure))<>'af5f755d8a1e8c6cbf9c22e955c4c7d5' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
 if md5(pg_get_functiondef('payroll_private.calculate(uuid,date)'::regprocedure))<>'a3ef0863a115e6ed385305b520c5079f' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
 if md5(pg_get_functiondef('payroll_private.late_plan(uuid,date)'::regprocedure))<>'517025ab29287b8e80817e09f8cad1c2' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
 if md5(pg_get_functiondef('payroll_private.attendance_register_rows(uuid,date)'::regprocedure))<>'362541768fbb7032921f1f468cb4eced' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
 if md5(pg_get_functiondef('payroll_private.attendance_period_hash(uuid,date)'::regprocedure))<>'c408db0de3e5546baa3bd1d04a4aac4d' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
 if md5(pg_get_functiondef('payroll_private.fingerprint(uuid)'::regprocedure))<>'cdd8538087062f03148e42f0f7019f48' then raise exception 'Payroll functions changed; rebuild and review the holiday migration before deployment';end if;
end $guard$;
-- END CORE VERSION GUARD

create table payroll_private.holiday_calendar(
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.payroll_companies(id),
 name text not null check(length(name) between 2 and 160),from_date date not null,to_date date not null,
 departments text[] not null default '{}',active boolean not null default true,revision int not null default 1,
 updated_by uuid not null,updated_at timestamptz not null default now(),
 check(to_date>=from_date and to_date-from_date<=365));
create index holiday_calendar_company_dates on payroll_private.holiday_calendar(company_id,from_date,to_date) where active;
alter table payroll_private.holiday_calendar enable row level security;
revoke all on payroll_private.holiday_calendar from public,anon,authenticated;
create table payroll_private.holiday_events(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.payroll_companies(id),holiday_id uuid not null,actor uuid not null,action text not null,before_record jsonb,after_record jsonb,created_at timestamptz not null default now());
alter table payroll_private.holiday_events enable row level security;
revoke all on payroll_private.holiday_events from public,anon,authenticated;

create function payroll_private.holiday_signature(cid uuid,sid uuid default null,first_date date default '2000-01-01',last_date date default '2099-12-31') returns text
language sql stable security definer set search_path='' as $$
 select case when coalesce((c.settings->>'department_holidays_enabled')::boolean,false) then
 (select jsonb_agg(jsonb_build_array(h.id,h.from_date,h.to_date,h.departments) order by h.id)::text
  from payroll_private.holiday_calendar h where h.company_id=cid and h.active and h.from_date<=last_date and h.to_date>=first_date
  and (sid is null or cardinality(h.departments)=0 or exists(select 1 from public.payroll_staff st where st.id=sid and st.company_id=cid and st.department=any(h.departments)))) end
 from public.payroll_companies c where c.id=cid
$$;
revoke all on function payroll_private.holiday_signature(uuid,uuid,date,date) from public,anon,authenticated;

create function payroll_private.working_day(cid uuid,sid uuid,work_date date) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(c.settings->'working_days' @> jsonb_build_array(extract(isodow from work_date)::int)
  and not c.settings->'holidays' @> jsonb_build_array(work_date::text)
  and not (coalesce((c.settings->>'department_holidays_enabled')::boolean,false) and exists(
   select 1 from payroll_private.holiday_calendar h where h.company_id=cid and h.active and work_date between h.from_date and h.to_date
   and (cardinality(h.departments)=0 or st.department=any(h.departments)))),false)
 from public.payroll_companies c join public.payroll_staff st on st.company_id=c.id and st.id=sid where c.id=cid
$$;
revoke all on function payroll_private.working_day(uuid,uuid,date) from public,anon,authenticated;

create function payroll_private.holidays(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid;uid uuid=auth.uid();op text=coalesce(payload->>'mode','load');r text;hid uuid;old payroll_private.holiday_calendar;next_row payroll_private.holiday_calendar;dep text[];f date;t date;own_dep text;items jsonb;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and not coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Confirmed login and personal password required';end if;
 r=payroll_private.role(cid);if r is null then raise exception 'Company access required';end if;
 if not payroll_private.module_enabled(cid,'leave') then raise exception 'Leave module is unavailable';end if;
 if op not in ('load','save','cancel') then raise exception 'Unknown holiday action';end if;
 if op<>'load' then
  if r not in ('admin','hr') then raise exception 'HR or Administrator access required';end if;
  perform 1 from public.payroll_companies where id=cid for update;
  if not exists(select 1 from public.payroll_companies where id=cid and coalesce((settings->>'department_holidays_enabled')::boolean,false)) then raise exception 'Department holiday calendar is not enabled';end if;
  hid=nullif(payload->>'id','')::uuid;
  if hid is not null then
   select * into old from payroll_private.holiday_calendar where id=hid and company_id=cid for update;
   if not found then raise exception 'Holiday not found in this company';end if;
  end if;
  if (payload->>'expected_revision')::int is distinct from coalesce(old.revision,0) then raise exception 'Holiday changed; reload before saving';end if;
  if op='save' then
   if length(trim(coalesce(payload->>'name',''))) not between 2 and 160 then raise exception 'Enter a holiday name (2-160 characters)';end if;
   f=(payload->>'from_date')::date;t=(payload->>'to_date')::date;
   if f is null or t is null or f<'2000-01-01' or t>'2099-12-31' or t<f or t-f>365 then raise exception 'Choose a date range up to 366 days, from 2000 to 2099';end if;
   if payload->>'scope'='all' then dep='{}';
   elsif payload->>'scope'='selected' then
    if jsonb_typeof(payload->'departments') is distinct from 'array' then raise exception 'Select departments';end if;
    select array_agg(distinct value order by value) into dep from jsonb_array_elements_text(payload->'departments');
    if coalesce(cardinality(dep),0)=0 or exists(select 1 from unnest(dep) selected where not exists(select 1 from public.payroll_staff st where st.company_id=cid and st.department=selected)) then raise exception 'Select existing departments in this company';end if;
   else raise exception 'Choose all departments or selected departments';end if;
  else
   if hid is null or not old.active then raise exception 'Choose an active holiday to cancel';end if;f=old.from_date;t=old.to_date;dep=old.departments;
  end if;
  if exists(select 1 from public.payroll_runs pr where pr.company_id=cid and pr.status in ('locked','released','paid') and ((pr.month<=t and (pr.month+interval '1 month')::date>f) or (old.id is not null and pr.month<=old.to_date and (pr.month+interval '1 month')::date>old.from_date)))
   or exists(select 1 from payroll_private.attendance_periods ap where ap.company_id=cid and ap.status='finalized' and ((ap.month<=t and (ap.month+interval '1 month')::date>f) or (old.id is not null and ap.month<=old.to_date and (ap.month+interval '1 month')::date>old.from_date))) then raise exception 'Reopen confirmed attendance before changing holidays; locked payroll requires a reviewed adjustment';end if;
  if exists(select 1 from public.payroll_leaves l join public.payroll_staff st on st.id=l.staff_id and st.company_id=cid where l.company_id=cid and l.status in ('submitted','approved') and
    ((l.from_date<=t and l.to_date>=f and (cardinality(dep)=0 or st.department=any(dep))) or
     (old.id is not null and l.from_date<=old.to_date and l.to_date>=old.from_date and (cardinality(old.departments)=0 or st.department=any(old.departments))))) then raise exception 'Resolve overlapping submitted or approved leave before changing this holiday calendar';end if;
  if op='save' then
   insert into payroll_private.holiday_calendar(id,company_id,name,from_date,to_date,departments,revision,updated_by)
   values(coalesce(hid,gen_random_uuid()),cid,trim(payload->>'name'),f,t,dep,coalesce(old.revision,0)+1,uid)
   on conflict(id) do update set name=excluded.name,from_date=excluded.from_date,to_date=excluded.to_date,departments=excluded.departments,active=true,revision=excluded.revision,updated_by=uid,updated_at=now() returning * into next_row;
  else update payroll_private.holiday_calendar set active=false,revision=revision+1,updated_by=uid,updated_at=now() where id=hid and company_id=cid returning * into next_row;end if;
  insert into payroll_private.holiday_events(company_id,holiday_id,actor,action,before_record,after_record) values(cid,next_row.id,uid,op,case when old.id is not null then to_jsonb(old) end,to_jsonb(next_row));
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'holiday_'||op,next_row.id::text);
 end if;
 if r='staff' then select department into own_dep from public.payroll_staff where company_id=cid and user_id=uid;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'name',h.name,'from_date',h.from_date,'to_date',h.to_date,'departments',h.departments,'active',h.active,'revision',h.revision) order by h.from_date,h.name),'[]') into items from payroll_private.holiday_calendar h where h.company_id=cid and (r in ('admin','hr') or h.active) and (r<>'staff' or cardinality(h.departments)=0 or own_dep=any(h.departments));
 return jsonb_build_object('enabled',coalesce((select (settings->>'department_holidays_enabled')::boolean from public.payroll_companies where id=cid),false),'items',items,'departments',case when r in ('admin','hr') then coalesce((select jsonb_agg(distinct department order by department) from public.payroll_staff where company_id=cid),'[]') else '[]'::jsonb end);
end$$;
revoke all on function payroll_private.holidays(jsonb) from public,anon;
grant execute on function payroll_private.holidays(jsonb) to authenticated;
create function public.payroll_holidays(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.holidays(payload)$$;
revoke all on function public.payroll_holidays(jsonb) from public,anon;
grant execute on function public.payroll_holidays(jsonb) to authenticated;


CREATE OR REPLACE FUNCTION payroll_private.dispatch(action text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid=auth.uid(); cid uuid=nullif(payload->>'company_id','')::uuid; r text; sid uuid=nullif(payload->>'staff_id','')::uuid; rec uuid=nullif(payload->>'id','')::uuid;
 c public.payroll_companies; st public.payroll_staff; le public.payroll_leaves; late_review public.payroll_late_reviews; late_plan jsonb; m date; cl_days numeric; doc public.payroll_documents; inc public.payroll_increments; run public.payroll_runs;
 v_email text; target_uid uuid; reqid uuid=nullif(payload->>'request_id','')::uuid; j jsonb; day date; units numeric; reserved numeric; balance numeric; paid_type boolean; out jsonb; score numeric;
begin
 if uid is null then raise exception 'Authentication required';end if;
 if not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirm your email before accessing payroll';end if;
 if action='staff_password_ready' then
  if not exists(select 1 from public.payroll_staff s join auth.users u on u.id=s.user_id join public.payroll_members m on m.company_id=s.company_id and m.user_id=u.id where u.id=uid and s.status='active' and u.raw_app_meta_data->>'payroll_staff_id'=s.id::text and u.raw_app_meta_data->>'payroll_company_id'=s.company_id::text) then raise exception 'Staff account activation must finish before changing the temporary password';end if;
  return jsonb_build_object('ready',true);
 end if;
 if exists(select 1 from auth.users where id=uid and coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then
  if action='bootstrap' then return jsonb_build_object('password_change_required',true,'companies','[]'::jsonb);end if;
  raise exception 'Change your temporary password before accessing payroll';
 end if;
 if action='bootstrap' then
  select lower(u.email) into v_email from auth.users u where id=uid;
  for st in select * from public.payroll_staff where lower(payroll_staff.email)=v_email and status='active' and (user_id is null or user_id=uid) loop
   update public.payroll_staff set user_id=uid where id=st.id;
   insert into public.payroll_members(company_id,user_id,role) values(st.company_id,uid,'staff') on conflict do nothing;
  end loop;
  return jsonb_build_object('companies',coalesce((select jsonb_agg(case when payroll_private.role(co.id)='staff' then jsonb_build_object('id',co.id,'name',co.name,'address',co.address,'settings',jsonb_build_object('working_days',co.settings->'working_days','holidays',co.settings->'holidays')) else to_jsonb(co) end||jsonb_build_object('role',payroll_private.display_role(co.id))) from public.payroll_companies co join public.payroll_members m on m.company_id=co.id where m.user_id=uid and payroll_private.role(co.id) is not null),'[]'::jsonb));
 end if;
 if action='company_create' then
  if not exists(select 1 from public.payroll_members where user_id=uid and payroll_private.role(company_id)='admin') then raise exception 'Administrator access required';end if;
  insert into public.payroll_companies(name,address) values(nullif(trim(payload->>'name'),''),coalesce(payload->>'address','')) returning id into cid;
  insert into public.payroll_members values(cid,uid,'admin');
  insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid) values(cid,'CL',12,true),(cid,'SL',12,true),(cid,'EL',0,true),(cid,'LWP',0,false);
  return jsonb_build_object('id',cid);
 end if;
 r=payroll_private.role(cid);
 if r is null then raise exception 'No access to this company';end if;
 if r='staff' and action not in ('state','leave_apply','leave_withdraw') then raise exception 'Staff access is limited to own leave, balances, rules, holidays and released payslips';end if;
 if r='hr' and action not in ('state','staff_save','staff_roster_import','staff_delete','attendance_save','attendance_report','punch_import','late_month','late_review','late_reopen','leave_apply','leave_withdraw','leave_decide','leave_credit','leave_policy','leave_group_set','document_save','document_decide','document_ack') then raise exception 'HR access is limited to staff entry, attendance/biometric leave, leave administration and letters';end if;
 if action='staff_login_prepare' then
  if r<>'admin' then raise exception 'Full company access required';end if;
  select * into st from public.payroll_staff where id=sid and company_id=cid and status='active';if not found then raise exception 'Active staff not found in this company';end if;
  return jsonb_build_object('staff_id',st.id,'username',st.login_name,'email',st.login_name||'@staff.payroll.invalid','linked',st.user_id is not null,'pending_user_id',(select u.id from auth.users u where lower(u.email)=st.login_name||'@staff.payroll.invalid' and u.raw_app_meta_data->>'payroll_staff_id'=st.id::text and u.raw_app_meta_data->>'payroll_company_id'=cid::text));
 end if;
 if action='late_month' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a month';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'code',s.code,'name',s.name,'can_review',payroll_private.late_can_review(s.id),'plan',payroll_private.late_plan(s.id,m),'review',(select to_jsonb(l) from public.payroll_late_reviews l where l.staff_id=s.id and l.month=m and l.status='active')) order by s.code) from public.payroll_staff s where s.company_id=cid and s.joining_date<(m+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>=m and (r in ('admin','hr','accountant') or payroll_private.own(s.id) or payroll_private.late_can_review(s.id))),'[]'::jsonb);
 end if;
 if action='attendance_report' then
  return coalesce((select jsonb_agg(a order by work_date,staff_id) from public.payroll_attendance a where company_id=cid and work_date>=date_trunc('month',(payload->>'month')::date)::date and work_date<(date_trunc('month',(payload->>'month')::date)+interval '1 month')::date and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id)))),'[]'::jsonb);
 end if;
 if action='state' then
  out=jsonb_build_object(
   'staff',coalesce((select jsonb_agg(s order by code) from public.payroll_staff s where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(id) or (r='manager' and payroll_private.team(id)))),'[]'::jsonb),
   'staff_details',coalesce((select jsonb_agg(d) from public.payroll_staff_details d where company_id=cid and (r in ('admin','hr') or payroll_private.own(staff_id))),'[]'::jsonb),
   'profiles',coalesce((select jsonb_agg(p) from public.payroll_profiles p where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'salaries',coalesce((select jsonb_agg(s order by effective_from) from public.payroll_salaries s where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'attendance',coalesce((select jsonb_agg(a) from (select * from public.payroll_attendance where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id))) order by work_date desc,id limit 2000)a),'[]'::jsonb),
   'punches',coalesce((select jsonb_agg(p) from (select * from public.payroll_punches where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id)) order by event_time desc limit 500) p),'[]'::jsonb),
   'policies',coalesce((select jsonb_agg(p) from public.payroll_leave_policies p where company_id=cid),'[]'::jsonb),
   'leave_routing',jsonb_build_object('offices',coalesce((select jsonb_agg(jsonb_build_object('office',a.office,'ready',a.user_id is not null and payroll_private.role(cid) is not null and exists(select 1 from public.payroll_members m where m.company_id=cid and m.user_id=a.user_id and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='separated') and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='active'))))) from public.payroll_leave_approvers a where a.company_id=cid),'[]'::jsonb),'approvers',case when r='admin' then coalesce((select jsonb_agg(jsonb_build_object('office',a.office,'email',u.email)) from public.payroll_leave_approvers a left join auth.users u on u.id=a.user_id where a.company_id=cid),'[]'::jsonb) else '[]'::jsonb end),
   'leaves',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('staff_name',(select s.name from public.payroll_staff s where s.id=l.staff_id),'approval_office',coalesce(l.approval_office,payroll_private.leave_office(l.staff_id)),'can_decide',payroll_private.leave_can_decide(l.id)) order by created_at desc) from public.payroll_leaves l where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or payroll_private.leave_can_decide(id))),'[]'::jsonb),
   'documents',coalesce((select jsonb_agg(d order by created_at desc) from public.payroll_documents d where company_id=cid and (r in ('admin','hr') or (payroll_private.own(staff_id) and status in ('issued','acknowledged')))),'[]'::jsonb),
   'assessments',coalesce((select jsonb_agg(a order by created_at desc) from public.payroll_assessments a where company_id=cid and (r in ('admin','hr') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id)))),'[]'::jsonb),
   'increments',coalesce((select jsonb_agg(i) from public.payroll_increments i where company_id=cid and (r in ('admin','hr','accountant') or (payroll_private.own(staff_id) and status='approved'))),'[]'::jsonb),
   'runs',coalesce((select jsonb_agg(p order by month desc) from public.payroll_runs p where company_id=cid and (r in ('admin','hr','accountant') or (r='staff' and status in ('released','paid')))),'[]'::jsonb),
   'lines',coalesce((select jsonb_agg(l) from public.payroll_lines l where company_id=cid and (r in ('admin','hr','accountant') or (payroll_private.own(staff_id) and exists(select 1 from public.payroll_runs where id=l.run_id and status in ('released','paid'))))),'[]'::jsonb),
   'deposits',coalesce((select jsonb_agg(d order by created_at) from public.payroll_deposits d where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'audit',case when r='admin' then coalesce((select jsonb_agg(a) from (select * from public.payroll_audit where company_id=cid order by id desc limit 50)a),'[]'::jsonb) else '[]'::jsonb end);
  if r='staff' then
   out=out||jsonb_build_object('staff_details','[]'::jsonb,'profiles','[]'::jsonb,'salaries','[]'::jsonb,'attendance','[]'::jsonb,'punches','[]'::jsonb,'documents','[]'::jsonb,'assessments','[]'::jsonb,'increments','[]'::jsonb,'deposits','[]'::jsonb,'leave_routing','{}'::jsonb,
   'runs',coalesce((select jsonb_agg(prun) from public.payroll_runs prun where prun.company_id=cid and payroll_private.staff_run_access(prun.id)),'[]'::jsonb));
  elsif r='hr' then
   out=out||jsonb_build_object('salaries','[]'::jsonb,'assessments','[]'::jsonb,'increments','[]'::jsonb,'deposits','[]'::jsonb,'runs','[]'::jsonb,'lines','[]'::jsonb);
  end if;
  return out;
 end if;
 if action in ('staff_save','initial_salary','increment_save') and payload->>'salary_mode'='consolidated' then
  payload=payload||jsonb_build_object('basic',0,'da',0,'hra',0,'cca',0,'other',coalesce(payload->>'consolidated_amount',payload->>'other','0'));
 end if;
 -- Lock company first for all writes. This serializes payroll locking with staff/leave/input edits.
 select * into c from public.payroll_companies where id=cid for update;
 if reqid is not null then
  select response into out from payroll_private.requests where token=reqid and user_id=uid and company_id=cid and operation=action;
  if found then
   if not exists(select 1 from payroll_private.requests where token=reqid and request_hash=md5(payload::text)) then raise exception 'Request ID reused with different data';end if;
   return out;end if;
  if exists(select 1 from payroll_private.requests where token=reqid) then raise exception 'Request ID collision';end if;
 end if;
 if sid is not null then select * into st from public.payroll_staff where id=sid and company_id=cid for update;if not found then raise exception 'Staff not found in this company';end if;end if;
 if action='staff_login_link' then
  if r<>'admin' or sid is null or st.status<>'active' then raise exception 'Full company access and active staff required';end if;
  if st.user_id is not null then raise exception 'Staff login is already linked';end if;
  target_uid=nullif(payload->>'user_id','')::uuid;
  if not exists(select 1 from auth.users u where u.id=target_uid and lower(u.email)=st.login_name||'@staff.payroll.invalid' and u.email_confirmed_at is not null and u.raw_app_meta_data->>'payroll_staff_id'=st.id::text and u.raw_app_meta_data->>'payroll_company_id'=cid::text and (u.raw_app_meta_data->>'payroll_password_change_required')::boolean) then raise exception 'Account was not provisioned for this staff record';end if;
  if exists(select 1 from public.payroll_staff where user_id=target_uid) then raise exception 'Account is already linked to staff';end if;
  update public.payroll_staff set user_id=target_uid,email=st.login_name||'@staff.payroll.invalid' where id=sid;
  insert into public.payroll_members(company_id,user_id,role) values(cid,target_uid,'staff') on conflict do nothing;rec=sid;
 elsif action in ('late_review','late_reopen') then
  if sid is null or not payroll_private.late_can_review(sid) then raise exception 'Assigned Principal / HR approval required; self-review is forbidden';end if;
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a month';end if;
  if length(trim(coalesce(payload->>'reason','')))<3 then raise exception 'Enter a review reason';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month=m and status in ('locked','released','paid')) then raise exception 'Payroll month is locked; use the adjustment process';end if;
  select * into late_review from public.payroll_late_reviews where staff_id=sid and month=m and status='active' for update;
  if action='late_reopen' then
   if late_review.id is null then raise exception 'No active late review to reopen';end if;
   if late_review.cl_units>0 then
    update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array['CL'],to_jsonb(coalesce((leave_balances->>'CL')::numeric,0)+late_review.cl_units)) where id=sid;
    insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,'CL',late_review.cl_units,'Reopened late review '||late_review.id,'late_cl_refund');
   end if;
   update public.payroll_late_reviews set status='reopened',reopened_by=uid,reopened_at=now(),reopen_reason=trim(payload->>'reason') where id=late_review.id;rec=late_review.id;
  else
   if late_review.id is not null then raise exception 'Reopen the existing late review before changing decisions';end if;
   late_plan=payroll_private.late_plan(sid,m);
   if payload->>'source_hash' is distinct from late_plan->>'source_hash' then raise exception 'Attendance or leave changed; reload the monthly late report';end if;
   if jsonb_typeof(payload->'decisions') is distinct from 'array' then raise exception 'Review every uncovered late arrival';end if;
   if jsonb_array_length(payload->'decisions')<>(select count(*) from jsonb_array_elements(late_plan->'events') e where not (e->>'covered')::boolean) or jsonb_array_length(payload->'decisions')=0 then raise exception 'Review every uncovered late arrival exactly once';end if;
   if (select count(distinct d->>'attendance_id') from jsonb_array_elements(payload->'decisions') d)<>jsonb_array_length(payload->'decisions') then raise exception 'Duplicate late decision';end if;
   for j in select * from jsonb_array_elements(payload->'decisions') loop
    if coalesce(j->>'decision','') not in ('lop','cl') or not exists(select 1 from jsonb_array_elements(late_plan->'events') e where e->>'attendance_id'=j->>'attendance_id' and not (e->>'covered')::boolean) then raise exception 'Invalid late decision';end if;
   end loop;
   select count(*)*0.5 into cl_days from jsonb_array_elements(payload->'decisions') d where d->>'decision'='cl';
   if cl_days>0 then
    if not exists(select 1 from public.payroll_leave_policies where company_id=cid and code='CL' and paid) then raise exception 'A paid CL policy is required';end if;
    select coalesce(sum(l.units),0) into reserved from public.payroll_leaves l where l.staff_id=sid and l.leave_type='CL' and l.status='submitted';
    if coalesce((st.leave_balances->>'CL')::numeric,0)-reserved<cl_days then raise exception 'Insufficient unreserved Casual Leave balance';end if;
   end if;
   insert into public.payroll_late_reviews(company_id,staff_id,month,source_hash,plan,decisions,cl_units,reason,reviewed_by) values(cid,sid,m,late_plan->>'source_hash',late_plan,payload->'decisions',cl_days,trim(payload->>'reason'),uid) returning id into rec;
   if cl_days>0 then
    update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array['CL'],to_jsonb(coalesce((leave_balances->>'CL')::numeric,0)-cl_days)) where id=sid;
    insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,'CL',-cl_days,'Late review '||rec,'late_cl_debit');
   end if;
  end if;
 elsif action='leave_approver_set' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  if coalesce(payload->>'office','') not in ('principal','director','president','hr') then raise exception 'Choose a valid approval office';end if;
  target_uid=null;
  if nullif(trim(payload->>'email'),'') is not null then
   select u.id into target_uid from auth.users u join public.payroll_members m on m.user_id=u.id and m.company_id=cid
   where lower(u.email)=lower(trim(payload->>'email')) and u.email_confirmed_at is not null
   and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=u.id and s.status='separated')
   and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=u.id and s.status='active'));
   if target_uid is null then raise exception 'Approver needs a confirmed, active account in this company';end if;
  end if;
  insert into public.payroll_leave_approvers(company_id,office,user_id,updated_by) values(cid,payload->>'office',target_uid,uid)
  on conflict(company_id,office) do update set user_id=excluded.user_id,updated_by=excluded.updated_by,updated_at=now();
 elsif action='leave_group_set' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null then raise exception 'Choose a staff member';end if;
  if coalesce(payload->>'leave_group','') not in ('auto','teacher_staff','principal','director','support','president') then raise exception 'Choose a valid leave group';end if;
  update public.payroll_staff set leave_group=nullif(payload->>'leave_group','auto') where id=sid;
 elsif action='settings' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  j=payload->'settings';
  if j ? 'pt_auto_slabs' and coalesce(j->>'pt_auto_slabs','') not in ('true','false') then raise exception 'Invalid PT slab setting';end if;
  if coalesce((j->>'pt_auto_slabs')::boolean,false) and (nullif(j->>'pt_effective_from','') is null or (j->>'pt_effective_from')::date<>date_trunc('month',(j->>'pt_effective_from')::date)::date) then raise exception 'Select the first day of the PT policy month';end if;
  if not j ?& array['working_days','holidays','pf_rate','pf_employer_rate','pf_cap','esi_rate','esi_employer_rate','effective_from','deposit_cap','deposit_enabled','statutory_reviewed'] then raise exception 'Missing required policy settings';end if;
  if jsonb_typeof(j->'working_days')<>'array' or jsonb_array_length(j->'working_days')=0 then raise exception 'Set working weekdays';end if;
  if (j->>'pf_rate')::numeric not between 0 and 100 or (j->>'pf_employer_rate')::numeric not between 0 and 100 or (j->>'esi_rate')::numeric not between 0 and 100 or (j->>'esi_employer_rate')::numeric not between 0 and 100 or (j->>'pf_cap')::numeric<0 or (j->>'deposit_cap')::numeric<0 then raise exception 'Invalid rates or caps';end if;
  if (j->>'deposit_enabled')::boolean and ((j->>'deposit_cap')::numeric<=0 or length(coalesce(j->>'deposit_policy',''))<15) then raise exception 'Set a positive deposit cap and reviewed policy reference';end if;
  update public.payroll_companies set name=nullif(trim(payload->>'name'),''),address=coalesce(payload->>'address',''),settings=j where id=cid;
 elsif action='member_grant' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  select id into target_uid from auth.users where lower(auth.users.email)=lower(payload->>'email') and email_confirmed_at is not null;
  if target_uid is null then raise exception 'This email must first have a confirmed Supabase account';end if;
  if target_uid=uid then raise exception 'Cannot change your own administrator role';end if;
  if payload->>'role'='staff' and not exists(select 1 from public.payroll_staff where company_id=cid and lower(payroll_staff.email)=lower(payload->>'email') and status='active') then raise exception 'Create the staff master first';end if;
  insert into public.payroll_members values(cid,target_uid,payload->>'role') on conflict(company_id,user_id) do update set role=excluded.role;
 elsif action='staff_roster_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Import 1 to 500 staff rows';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   if nullif(trim(j->>'code'),'') is null or nullif(trim(j->>'name'),'') is null or nullif(j->>'joining_date','') is null then raise exception 'Staff code, name and joining date are required';end if;
   if exists(select 1 from public.payroll_staff where company_id=cid and lower(code)=lower(trim(j->>'code'))) then raise exception 'Staff code already exists';end if;
   if jsonb_typeof(j->'personal_details') is distinct from 'object' or jsonb_typeof(j->'source_records') is distinct from 'array' then raise exception 'Invalid personnel details';end if;
   if exists(select 1 from jsonb_object_keys(j->'personal_details') k where not (k=ANY(array['S NO','Staff Name','Staff Code','Biometric Code','Staff ERPCode','Staff Department Name','Date Of Birth','Sex','Marital Status','Marriage Anniversary','Email','Alternate Email','Mobile No','Alternate No','Emergency No','Whatsapp No','Father Name','Father Occupation','Father PhoneNo','Spouse Name','Spouse PhoneNo','Spouse Ocupation','Address','Landmark1','Landmark2','Country Name','State Name','City Name','AdhaarCard No','PANCard No','Passport No','Government ID','Caste','Sub Caste','Nationality','CitizenShip','Religion','BloodGroup','Bank Name','Bank AccountNo','EPFNo','UAN','ESINo','Bank BranchName','Bank CityName','Bank StateName','Staff Payroll Entity','IFSCCode','Designation','Specialization','Qualification','CTET Qualified','Trained As','Date Of Joining','Date Of InActive','Employment Status','Previous Experience','Experience','Total Experience','Previous InstitutionName','Previous Designation','Security Deposit','Date','Payment Mode','Remarks','UserType Name','AccessLevel','IsDivorced','MotherName','Employment Category','BED Course','Subjects Assigned','NameAsPerBank']::text[]))) then raise exception 'Unknown personnel field';end if;
   insert into public.payroll_staff(company_id,code,name,email,department,designation,joining_date,leaving_date,status,service_status,biometric_id,leave_balances,erp_code,employment_status,employment_category)
   values(cid,trim(j->>'code'),trim(j->>'name'),null,coalesce(j->>'department',''),coalesce(j->>'designation',''),(j->>'joining_date')::date,nullif(j->>'leaving_date','')::date,
    case when nullif(j->>'leaving_date','')::date<=current_date then 'separated' else 'active' end,'imported',nullif(j->>'biometric_id',''),'{}',coalesce(j->'personal_details'->>'Staff ERPCode',''),coalesce(j->'personal_details'->>'Employment Status',''),coalesce(j->'personal_details'->>'Employment Category','')) returning id into sid;
   insert into public.payroll_profiles(staff_id,company_id,bank_account,ifsc,pan,uan,esi_number) values(sid,cid,coalesce(j->>'bank_account',''),coalesce(j->>'ifsc',''),coalesce(j->>'pan',''),coalesce(j->>'uan',''),coalesce(j->>'esi_number',''));
   insert into public.payroll_staff_details(staff_id,company_id,details,source_records) values(sid,cid,j->'personal_details',j->'source_records');
   units=units+1;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='staff_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Import 1 to 500 staff rows';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   perform payroll_private.dispatch('staff_save',(j - 'staff_id' - 'id' - 'request_id')||jsonb_build_object('company_id',cid,'staff_id',null,'request_id',null));
   units=units+1;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='staff_delete' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null or payload->>'confirm_code' is distinct from st.code then raise exception 'Confirm the staff code';end if;
  if st.user_id is not null then raise exception 'Linked staff cannot be deleted; use authorized separation to retain history';end if;
  if exists(select 1 from public.payroll_attendance where staff_id=sid) or exists(select 1 from public.payroll_punches where staff_id=sid)
   or exists(select 1 from public.payroll_leaves where staff_id=sid) or exists(select 1 from public.payroll_leave_ledger where staff_id=sid)
   or exists(select 1 from public.payroll_lines where staff_id=sid) or exists(select 1 from public.payroll_deposits where staff_id=sid)
   or exists(select 1 from public.payroll_documents where staff_id=sid) or exists(select 1 from public.payroll_assessments where staff_id=sid)
   or exists(select 1 from public.payroll_increments where staff_id=sid)
   or (select count(*) from public.payroll_salaries where staff_id=sid)>1
  then raise exception 'Staff has history and cannot be deleted; use authorized separation';end if;
  delete from public.payroll_profiles where staff_id=sid;
  delete from public.payroll_salaries where staff_id=sid;
  delete from public.payroll_staff where id=sid and company_id=cid;
 elsif action='staff_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if nullif(trim(payload->>'code'),'') is null or nullif(trim(payload->>'name'),'') is null or nullif(payload->>'joining_date','') is null then raise exception 'Code, name and joining date are required';end if;
  if sid is null and exists(select 1 from public.payroll_staff where company_id=cid and (lower(code)=lower(trim(payload->>'code')) or lower(email)=lower(trim(payload->>'email')))) then raise exception 'Staff code or email already exists';end if;
  if nullif(payload->>'email','') is not null and payload->>'email' !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Enter a valid email';end if;
  if sid is null then
   insert into public.payroll_staff(company_id,code,name,email,department,designation,joining_date,biometric_id,probation_end)
   values(cid,nullif(trim(payload->>'code'),''),nullif(trim(payload->>'name'),''),nullif(lower(trim(payload->>'email')),''),coalesce(payload->>'department',''),coalesce(payload->>'designation',''),(payload->>'joining_date')::date,nullif(payload->>'biometric_id',''),nullif(payload->>'probation_end','')::date) returning id into sid;
   insert into public.payroll_profiles(staff_id,company_id) values(sid,cid);
   if r<>'hr' then
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,cca,hod_allowance,salary_mode,deposit_eligible_override,pt_override,approved_by)
   values(cid,sid,(payload->>'joining_date')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,coalesce((payload->>'cca')::numeric,0),coalesce((payload->>'hod_allowance')::numeric,0),coalesce(payload->>'salary_mode','component'),(payload->>'deposit_eligible_override')::boolean,nullif(payload->>'pt_override','')::numeric,uid);
   end if;
  else
   if nullif(lower(trim(payload->>'email')),'') is distinct from st.email and st.user_id is not null then raise exception 'Linked email changes require account review';end if;
   update public.payroll_staff set email=nullif(lower(trim(payload->>'email')),''),name=nullif(trim(payload->>'name'),''),department=payload->>'department',designation=payload->>'designation',biometric_id=nullif(payload->>'biometric_id',''),probation_end=nullif(payload->>'probation_end','')::date where id=sid;
  end if;
  update public.payroll_profiles set bank_account=coalesce(payload->>'bank_account',''),ifsc=coalesce(payload->>'ifsc',''),pan=coalesce(payload->>'pan',''),uan=coalesce(payload->>'uan',''),esi_number=coalesce(payload->>'esi_number',''),pf_enabled=coalesce((payload->>'pf_enabled')::boolean,false),esi_enabled=coalesce((payload->>'esi_enabled')::boolean,false),deposit_eligible=coalesce((payload->>'deposit_eligible')::boolean,false) where staff_id=sid;
  if nullif(payload->>'manager_email','') is not null then
   select u.id into target_uid from auth.users u join public.payroll_members m on m.user_id=u.id where m.company_id=cid and m.role='manager' and lower(u.email)=lower(payload->>'manager_email');
   if target_uid is null then raise exception 'Assign a confirmed manager role before team mapping';end if;
   update public.payroll_staff set manager_user_id=target_uid where id=sid;
  end if;
  update public.payroll_staff set
   shift_name=coalesce(nullif(trim(payload->>'shift_name'),''),shift_name),
   shift_start=coalesce(nullif(payload->>'shift_start','')::time,shift_start),shift_end=coalesce(nullif(payload->>'shift_end','')::time,shift_end),
   break_minutes=coalesce(nullif(payload->>'break_minutes','')::int,break_minutes),
   late_grace=coalesce(nullif(payload->>'late_grace','')::int,late_grace),early_grace=coalesce(nullif(payload->>'early_grace','')::int,early_grace) where id=sid;
  if payload ? 'personal_details' then
   j=payload->'personal_details';
   if jsonb_typeof(j) is distinct from 'object' or exists(select 1 from jsonb_object_keys(j) k where not (k=ANY(array['S NO','Staff Name','Staff Code','Biometric Code','Staff ERPCode','Staff Department Name','Date Of Birth','Sex','Marital Status','Marriage Anniversary','Email','Alternate Email','Mobile No','Alternate No','Emergency No','Whatsapp No','Father Name','Father Occupation','Father PhoneNo','Spouse Name','Spouse PhoneNo','Spouse Ocupation','Address','Landmark1','Landmark2','Country Name','State Name','City Name','AdhaarCard No','PANCard No','Passport No','Government ID','Caste','Sub Caste','Nationality','CitizenShip','Religion','BloodGroup','Bank Name','Bank AccountNo','EPFNo','UAN','ESINo','Bank BranchName','Bank CityName','Bank StateName','Staff Payroll Entity','IFSCCode','Designation','Specialization','Qualification','CTET Qualified','Trained As','Date Of Joining','Date Of InActive','Employment Status','Previous Experience','Experience','Total Experience','Previous InstitutionName','Previous Designation','Security Deposit','Date','Payment Mode','Remarks','UserType Name','AccessLevel','IsDivorced','MotherName','Employment Category','BED Course','Subjects Assigned','NameAsPerBank']::text[]))) then raise exception 'Invalid personnel fields';end if;
   insert into public.payroll_staff_details(staff_id,company_id,details) values(sid,cid,j) on conflict(staff_id) do update set details=excluded.details;
   update public.payroll_staff set erp_code=coalesce(j->>'Staff ERPCode',''),employment_status=coalesce(j->>'Employment Status',''),employment_category=coalesce(j->>'Employment Category','') where id=sid;
  end if;
  rec=sid;
 elsif action='initial_salary' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null or exists(select 1 from public.payroll_salaries where staff_id=sid) then raise exception 'Initial salary already exists; use the increment workflow';end if;
  if (payload->>'effective_from')::date<st.joining_date then raise exception 'Salary cannot predate joining';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month>=(date_trunc('month',(payload->>'effective_from')::date))::date and status in ('locked','released','paid')) then raise exception 'Payroll is locked; use a reviewed adjustment';end if;
  insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,cca,hod_allowance,salary_mode,deposit_eligible_override,pt_override,approved_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,coalesce((payload->>'cca')::numeric,0),coalesce((payload->>'hod_allowance')::numeric,0),coalesce(payload->>'salary_mode','component'),(payload->>'deposit_eligible_override')::boolean,nullif(payload->>'pt_override','')::numeric,uid);
 elsif action='tax_inputs' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  update public.payroll_profiles set annual_tax=(payload->>'annual_tax')::numeric,tax_paid=(payload->>'tax_paid')::numeric,other_deductions=(payload->>'other_deductions')::numeric,pt=(payload->>'pt')::numeric where staff_id=sid;
 elsif action='attendance_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if (payload->>'to_date')::date<(payload->>'from_date')::date or (payload->>'to_date')::date-(payload->>'from_date')::date>31 then raise exception 'Choose at most 32 days';end if;
  for day in select generate_series((payload->>'from_date')::date,(payload->>'to_date')::date,interval '1 day')::date loop
   if day<st.joining_date or day>coalesce(st.leaving_date,'infinity'::date) then raise exception 'Attendance falls outside employment dates';end if;
   if exists(select 1 from public.payroll_late_reviews where staff_id=sid and month=date_trunc('month',day)::date and status='active') then raise exception 'Reopen this staff monthly late review before editing attendance';end if;
   if exists(select 1 from public.payroll_runs where company_id=cid and month=date_trunc('month',day)::date and status in ('locked','released','paid')) then raise exception 'Payroll month is locked; use a reviewed adjustment';end if;
   insert into public.payroll_attendance(company_id,staff_id,work_date,status,in_time,out_time,late_minutes,early_minutes,note,reviewed_by)
   values(cid,sid,day,payload->>'status',nullif(payload->>'in_time','')::time,nullif(payload->>'out_time','')::time,coalesce((payload->>'late_minutes')::int,0),coalesce((payload->>'early_minutes')::int,0),coalesce(payload->>'note',''),uid)
   on conflict(staff_id,work_date) do update set status=excluded.status,in_time=excluded.in_time,out_time=excluded.out_time,late_minutes=excluded.late_minutes,early_minutes=excluded.early_minutes,note=excluded.note,reviewed_by=uid;
   update public.payroll_attendance set raw_late_minutes=coalesce((payload->>'late_minutes')::int,0) where staff_id=sid and work_date=day;
   if coalesce((payload->>'calculate_shift')::boolean,false) then
    if nullif(payload->>'in_time','') is null or nullif(payload->>'out_time','') is null then raise exception 'In and out times are required for shift calculation';end if;
    if (day+((payload->>'out_time')::time)+case when coalesce((payload->>'out_next_day')::boolean,false) then interval '1 day' else interval '0 day' end) <= (day+((payload->>'in_time')::time)) then raise exception 'Out time must be after in time; select next-day out for overnight work';end if;
    update public.payroll_attendance set
     late_minutes=greatest(0,floor(extract(epoch from ((payload->>'in_time')::time-st.shift_start))/60)::int-st.late_grace),
     raw_late_minutes=greatest(0,floor(extract(epoch from ((payload->>'in_time')::time-st.shift_start))/60)::int),
     early_minutes=greatest(0,floor(extract(epoch from ((day+st.shift_end+case when st.shift_end<st.shift_start then interval '1 day' else interval '0 day' end)-(day+(payload->>'out_time')::time+case when coalesce((payload->>'out_next_day')::boolean,false) then interval '1 day' else interval '0 day' end)))/60)::int-st.early_grace),
     shift_snapshot=jsonb_build_object('name',st.shift_name,'start',st.shift_start,'end',st.shift_end,'break_minutes',st.break_minutes,'late_grace',st.late_grace,'early_grace',st.early_grace,'out_next_day',coalesce((payload->>'out_next_day')::boolean,false)) where staff_id=sid and work_date=day;
   else
    update public.payroll_attendance set shift_snapshot=null where staff_id=sid and work_date=day;
   end if;
  end loop;
 elsif action='punch_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_array_length(payload->'rows')>1000 then raise exception 'Import at most 1,000 punches per batch';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   select id into sid from public.payroll_staff where company_id=cid and biometric_id=j->>'biometric_id' and status='active';
   if sid is null then raise exception 'Unknown biometric ID: %',j->>'biometric_id';end if;
   insert into public.payroll_punches(company_id,staff_id,device_id,event_id,event_time,direction) values(cid,sid,nullif(j->>'device_id',''),nullif(j->>'event_id',''),(j->>'event_timestamp_iso8601')::timestamptz,lower(j->>'punch_direction')) on conflict(company_id,device_id,event_id) do nothing;
   if found then units=units+1;end if;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='leave_apply' then
  if not payroll_private.own(sid) then raise exception 'Apply leave through your own staff login';end if;
  v_email=payroll_private.leave_office(sid);
  if v_email is null then raise exception 'No leave approval policy for this staff group; contact HR';end if;
  select a.user_id into target_uid from public.payroll_leave_approvers a join public.payroll_members m on m.company_id=a.company_id and m.user_id=a.user_id
  where a.company_id=cid and a.office=v_email
  and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='separated')
  and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='active'));
  if target_uid is null then raise exception 'The % approver is not configured or inactive; contact your administrator',v_email;end if;
  if target_uid=uid then raise exception 'Self-approval route is not allowed; ask administrator to correct the approver';end if;
  if length(trim(payload->>'reason'))<3 then raise exception 'Enter a reason';end if;
  if (payload->>'to_date')::date<(payload->>'from_date')::date or (payload->>'to_date')::date-(payload->>'from_date')::date>366 then raise exception 'Invalid leave dates';end if;
  if (payload->>'from_date')::date<st.joining_date or (payload->>'to_date')::date>coalesce(st.leaving_date,'infinity'::date) then raise exception 'Leave falls outside employment';end if;
  if (payload->>'half_day')::boolean and payload->>'from_date'<>payload->>'to_date' then raise exception 'Half-day requests must use one date';end if;
  if exists(select 1 from public.payroll_leaves where staff_id=sid and status in ('submitted','approved') and daterange(from_date,to_date,'[]') && daterange((payload->>'from_date')::date,(payload->>'to_date')::date,'[]')) then raise exception 'Another leave request overlaps these dates';end if;
  select count(*) into units from generate_series((payload->>'from_date')::date,(payload->>'to_date')::date,interval '1 day')d where (case when coalesce((c.settings->>'department_holidays_enabled')::boolean,false) then payroll_private.working_day(cid,sid,d::date) else (c.settings->'working_days' @> jsonb_build_array(extract(isodow from d)::int) and not c.settings->'holidays' @> jsonb_build_array(d::date::text)) end);
  if (payload->>'half_day')::boolean then units=units/2;end if;
  if units<=0 then raise exception 'No working leave days in this request';end if;
  select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=payload->>'leave_type';
  if not found then raise exception 'Leave type not found';end if;
  if not exists(select 1 from payroll_private.effective_leave_policy(cid,sid,payload->>'leave_type') where active and (not coalesce((payload->>'half_day')::boolean,false) or half_day_allowed) and (max_days_per_request is null or units<=max_days_per_request)) then raise exception 'Leave type is inactive, half-day is not allowed, or request exceeds the working-day maximum';end if;
  select coalesce(sum(l.units),0) into reserved from public.payroll_leaves l where staff_id=sid and status='submitted' and leave_type=payload->>'leave_type';
  if paid_type and units+reserved>coalesce((st.leave_balances->>(payload->>'leave_type'))::numeric,0) then raise exception 'Insufficient available leave balance';end if;
  insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,half_day,units,reason,created_by,approval_office) values(cid,sid,payload->>'leave_type',(payload->>'from_date')::date,(payload->>'to_date')::date,(payload->>'half_day')::boolean,units,payload->>'reason',uid,v_email) returning id into rec;
 elsif action='leave_decide' then
  select * into le from public.payroll_leaves where id=rec and company_id=cid for update;if not found then raise exception 'Leave request not found';end if;
  select * into st from public.payroll_staff where id=le.staff_id for update;
  if not payroll_private.leave_can_decide(rec) then raise exception 'Only the assigned company approval office can decide this leave';end if;
  if le.created_by=uid then raise exception 'You cannot approve your own leave';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month between date_trunc('month',le.from_date)::date and date_trunc('month',le.to_date)::date and status in ('locked','released','paid')) then raise exception 'Affected payroll is locked; use adjustment process';end if;
  if payload->>'decision'='cancelled' then
   if le.status<>'approved' then raise exception 'Only approved leave can be cancelled here';end if;
   select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=le.leave_type;
   if paid_type then update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[le.leave_type],to_jsonb((leave_balances->>le.leave_type)::numeric+le.units)) where id=le.staff_id;insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,leave_id,event) values(cid,le.staff_id,le.leave_type,le.units,'Approved cancellation',le.id,'cancelled');end if;
  else
   if le.status<>'submitted' or payload->>'decision' not in ('approved','rejected') then raise exception 'Request is no longer pending';end if;
   if payload->>'decision'='approved' then
    select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=le.leave_type;
    if paid_type then
     balance=coalesce((st.leave_balances->>le.leave_type)::numeric,0);if balance<le.units then raise exception 'Insufficient leave balance';end if;
     update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[le.leave_type],to_jsonb(balance-le.units)) where id=le.staff_id;
     insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,leave_id,event) values(cid,le.staff_id,le.leave_type,-le.units,'Approved leave',le.id,'approved');
    end if;
   end if;
  end if;
  update public.payroll_leaves set status=payload->>'decision',reviewed_by=uid where id=rec;
 elsif action='leave_withdraw' then
  update public.payroll_leaves set status='cancelled' where id=rec and company_id=cid and created_by=uid and status='submitted';if not found then raise exception 'Only your pending request can be withdrawn';end if;
 elsif action='leave_credit' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if not exists(select 1 from public.payroll_leave_policies where company_id=cid and code=payload->>'leave_type' and paid) then raise exception 'Choose a valid paid leave type';end if;
  if coalesce(payload->>'units','') !~ '^-?[0-9]+(\.[0-9]+)?$' or (payload->>'units')::numeric=0 or mod((payload->>'units')::numeric,0.5)<>0 then raise exception 'Balance adjustment must be nonzero in half-day steps';end if;
  units=(payload->>'units')::numeric;balance=coalesce((st.leave_balances->>(payload->>'leave_type'))::numeric,0)+units;
  if balance<0 or length(coalesce(payload->>'reason',''))<3 then raise exception 'Invalid balance or reason';end if;
  update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[payload->>'leave_type'],to_jsonb(balance)) where id=sid;
  insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,payload->>'leave_type',units,payload->>'reason','adjustment');
 elsif action='leave_policy' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  j=payload||jsonb_build_object('code',upper(trim(payload->>'code')));
  if coalesce(j->>'code','') !~ '^[A-Z][A-Z0-9_]{0,15}$' then raise exception 'Use a leave code of 1–16 letters, numbers or underscores, starting with a letter';end if;
  if nullif(payload->>'original_code','') is not null and payload->>'original_code'<>j->>'code' then raise exception 'Leave code cannot be renamed';end if;
  if length(trim(coalesce(payload->>'name',j->>'code',''))) not between 1 and 80 or length(coalesce(payload->>'description',''))>4000 then raise exception 'Enter a leave name up to 80 characters and policy notes up to 4000';end if;
  if coalesce(payload->>'annual_entitlement','') !~ '^[0-9]+(\.[0-9]+)?$' or (payload->>'annual_entitlement')::numeric>366 or mod((payload->>'annual_entitlement')::numeric,0.5)<>0 then raise exception 'Annual entitlement must be 0–366 days in half-day steps';end if;
  if coalesce(payload->>'paid','') not in ('true','false') or coalesce(payload->>'active','true') not in ('true','false') or coalesce(payload->>'half_day_allowed','true') not in ('true','false') then raise exception 'Invalid leave rule option';end if;
  if nullif(payload->>'max_days_per_request','') is not null and (coalesce(payload->>'max_days_per_request','') !~ '^[0-9]+(\.[0-9]+)?$' or (payload->>'max_days_per_request')::numeric<=0 or (payload->>'max_days_per_request')::numeric>366 or mod((payload->>'max_days_per_request')::numeric,0.5)<>0) then raise exception 'Maximum per request must be 0.5–366 working days in half-day steps, or blank';end if;
  if coalesce((payload->>'creating')::boolean,false) and exists(select 1 from public.payroll_leave_policies where company_id=cid and code=j->>'code') then raise exception 'Leave code already exists; use Edit';end if;
  if exists(select 1 from public.payroll_leave_policies where company_id=cid and code=j->>'code' and paid<>(payload->>'paid')::boolean) then raise exception 'Paid/unpaid cannot change on an existing leave type; create a new code';end if;
  insert into public.payroll_leave_policies(company_id,code,name,annual_entitlement,paid,description,active,half_day_allowed,max_days_per_request)
  values(cid,j->>'code',trim(coalesce(payload->>'name',j->>'code')),(payload->>'annual_entitlement')::numeric,(payload->>'paid')::boolean,coalesce(payload->>'description',''),coalesce((payload->>'active')::boolean,true),coalesce((payload->>'half_day_allowed')::boolean,true),nullif(payload->>'max_days_per_request','')::numeric)
  on conflict(company_id,code) do update set name=excluded.name,annual_entitlement=excluded.annual_entitlement,description=excluded.description,active=excluded.active,half_day_allowed=excluded.half_day_allowed,max_days_per_request=excluded.max_days_per_request;
 elsif action='document_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if length(coalesce(payload->>'body',''))<30 then raise exception 'Letter content is too short';end if;
  insert into public.payroll_documents(company_id,staff_id,type,recipient,body,signatory,created_by,effective_date) values(cid,sid,payload->>'type',payload->>'recipient',payload->>'body',coalesce(payload->>'signatory',''),uid,nullif(payload->>'effective_date','')::date) returning id into rec;
 elsif action='document_decide' then
  select * into doc from public.payroll_documents where id=rec and company_id=cid for update;if not found then raise exception 'Document not found';end if;
  if payload->>'decision'='acknowledged' then
   if not payroll_private.own(doc.staff_id) or doc.status<>'issued' then raise exception 'Only the recipient can acknowledge an issued letter';end if;
  else
   if r<>'admin' then raise exception 'Authorized administrator required';end if;
   if doc.body ~ '\[[^\]]+\]' or trim(doc.signatory)='' then raise exception 'Resolve placeholders and signatory before approval';end if;
   if payload->>'decision'='approved' and doc.status='draft' then null;
   elsif payload->>'decision'='issued' and doc.status='approved' then null;
   else raise exception 'Invalid document transition';end if;
  end if;
  update public.payroll_documents set status=payload->>'decision',approved_by=case when payload->>'decision'='approved' then uid else approved_by end,number=case when payload->>'decision'='issued' then 'HR-'||upper(substr(id::text,1,8)) else number end,issued_at=case when payload->>'decision'='issued' then now() else issued_at end where id=rec;
 elsif action='assessment_save' then
  if r not in ('admin','hr') and not (r='manager' and payroll_private.team(sid)) then raise exception 'Assessment access required';end if;
  if st.user_id=uid then raise exception 'Cannot finalize your own assessment';end if;
  select sum((v->>'weight')::numeric),sum((v->>'weight')::numeric*(v->>'rating')::numeric)/100 into units,score from jsonb_array_elements(payload->'ratings')v;
  if units<>100 or exists(select 1 from jsonb_array_elements(payload->'ratings')v where (v->>'rating')::numeric not between 1 and 5 or (v->>'weight')::numeric<0) then raise exception 'Invalid assessment ratings or weights';end if;
  insert into public.payroll_assessments(company_id,staff_id,period,ratings,score,comments,created_by) values(cid,sid,payload->>'period',payload->'ratings',score,payload->>'comments',uid) returning id into rec;
 elsif action='increment_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if (payload->>'effective_from')::date<st.joining_date then raise exception 'Increment predates employment';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month>=(date_trunc('month',(payload->>'effective_from')::date))::date and status in ('locked','released','paid')) then raise exception 'Backdated change affects locked payroll; reviewed arrears workflow is required';end if;
  insert into public.payroll_increments(company_id,staff_id,effective_from,basic,da,hra,other,cca,hod_allowance,salary_mode,deposit_eligible_override,pt_override,reason,created_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,coalesce((payload->>'cca')::numeric,0),coalesce((payload->>'hod_allowance')::numeric,0),coalesce(payload->>'salary_mode','component'),(payload->>'deposit_eligible_override')::boolean,nullif(payload->>'pt_override','')::numeric,payload->>'reason',uid) returning id into rec;
 elsif action='increment_decide' then
  select * into inc from public.payroll_increments where id=rec and company_id=cid for update;if not found then raise exception 'Increment not found';end if;
  if payload->>'decision'='accountant_reviewed' and inc.status='recommended' and r in ('admin','accountant') and inc.created_by<>uid then update public.payroll_increments set status='accountant_reviewed',reviewed_by=uid where id=rec;
  elsif payload->>'decision'='approved' and inc.status='accountant_reviewed' and r='admin' then
   if exists(select 1 from public.payroll_runs where company_id=cid and month>=date_trunc('month',inc.effective_from)::date and status in ('locked','released','paid')) then raise exception 'Payroll was locked after recommendation; use reviewed arrears';end if;
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,cca,hod_allowance,salary_mode,deposit_eligible_override,pt_override,approved_by) values(cid,inc.staff_id,inc.effective_from,inc.basic,inc.da,inc.hra,inc.other,inc.cca,inc.hod_allowance,inc.salary_mode,inc.deposit_eligible_override,inc.pt_override,uid);
   update public.payroll_increments set status='approved',approved_by=uid where id=rec;
  elsif payload->>'decision'='rejected' and inc.status in ('recommended','accountant_reviewed') and r='admin' then update public.payroll_increments set status='rejected' where id=rec;
  else raise exception 'Requires independent accountant review followed by administrator approval';end if;
 elsif action='service_change' then
  if r<>'admin' then raise exception 'Authorized administrator required';end if;
  if payload->>'service_status' not in ('probation','confirmed','extended') then raise exception 'Invalid service status';end if;
  update public.payroll_staff set service_status=payload->>'service_status',probation_end=nullif(payload->>'probation_end','')::date where id=sid;
 elsif action='separate' then
  if r<>'admin' or payload->>'confirm'<>'SEPARATE' then raise exception 'Explicit administrator separation decision required';end if;
  if st.user_id=uid then raise exception 'Cannot separate your own account';end if;
  if (payload->>'leaving_date')::date>current_date then raise exception 'Future exits must be executed on the effective date';end if;
  if length(coalesce(payload->>'reason',''))<5 then raise exception 'Record the authorized decision reason';end if;
  update public.payroll_staff set status='separated',leaving_date=(payload->>'leaving_date')::date where id=sid;
 elsif action='deposit_refund' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  select coalesce(sum(amount),0) into balance from public.payroll_deposits where staff_id=sid;
  units=(payload->>'amount')::numeric;if units<=0 or units>balance or length(coalesce(payload->>'reason',''))<5 then raise exception 'Invalid refund amount or payment reference';end if;
  insert into public.payroll_deposits(company_id,staff_id,amount,reason,created_by) values(cid,sid,-units,payload->>'reason',uid);
 elsif action='payroll_calculate' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  rec=payroll_private.calculate(cid,(payload->>'month')::date);
 elsif action='payroll_decide' then
  select * into run from public.payroll_runs where id=rec and company_id=cid for update;if not found then raise exception 'Payroll not found';end if;
  if payload->>'decision' in ('hr_reviewed','accountant_reviewed','locked') then
   if run.input_hash<>payroll_private.fingerprint(cid) then raise exception 'Inputs changed; recalculate payroll before review';end if;
   if exists(select 1 from public.payroll_lines where run_id=rec and jsonb_array_length(issues)>0) then raise exception 'Resolve payroll exceptions before approval';end if;
  end if;
  if payload->>'decision'='hr_reviewed' and run.status='calculated' and r in ('admin','hr') then update public.payroll_runs set status='hr_reviewed',hr_by=uid where id=rec;
  elsif payload->>'decision'='accountant_reviewed' and run.status='hr_reviewed' and r in ('admin','accountant') and run.created_by<>uid then update public.payroll_runs set status='accountant_reviewed',accountant_by=uid where id=rec;
  elsif payload->>'decision'='locked' and run.status='accountant_reviewed' and r='admin' then
   update public.payroll_runs set status='locked',authorized_by=uid where id=rec;
   insert into public.payroll_deposits(company_id,staff_id,amount,reason,line_id,created_by) select cid,staff_id,(deductions->>'Security deposit')::numeric,'Payroll '||run.month,id,uid from public.payroll_lines where run_id=rec and (deductions->>'Security deposit')::numeric>0;
  elsif payload->>'decision'='released' and run.status='locked' and r='admin' then update public.payroll_runs set status='released' where id=rec;
  elsif payload->>'decision'='paid' and run.status='released' and r in ('admin','accountant') and length(coalesce(payload->>'payment_reference',''))>=5 then
   update public.payroll_lines set payment_reference=payload->>'payment_reference' where run_id=rec;update public.payroll_runs set status='paid' where id=rec;
  else raise exception 'Invalid transition; independent review or payment evidence may be missing';end if;
 else raise exception 'Unknown payroll action';end if;
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,action,coalesce(rec,sid)::text);
 out=coalesce(out,jsonb_build_object('id',coalesce(rec,sid),'ok',true));
 if reqid is not null then insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqid,cid,uid,action,md5(payload::text),out);end if;
 return out;
end$function$
;

CREATE OR REPLACE FUNCTION payroll_private.calculate(cid uuid, month_start date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.payroll_companies; s public.payroll_staff; p public.payroll_profiles; sal public.payroll_salaries; att public.payroll_attendance;
 day date; last_day date; rid uuid; ndays int; remaining int; factor numeric; units numeric; lop numeric; paid numeric;
 manual_deductions jsonb; flow_policy payroll_private.salary_flow_policies; flow_active boolean; flow_special numeric; flow_gross numeric; monthly_pt numeric; deposit_base numeric; deposit_all boolean; consolidated numeric; consolidated_days numeric; component_hod numeric; stat_wage numeric; cca numeric; hod numeric; b numeric; da numeric; hra numeric; other numeric; gross numeric; pf numeric; esi numeric; tds numeric; deposit numeric; balance numeric; wage numeric; deductions numeric;
 issues jsonb; lr public.payroll_leaves; is_work boolean; lrpaid boolean; late_plan jsonb;late_review public.payroll_late_reviews;late_valid boolean;late_lop numeric;
begin
 select * into c from public.payroll_companies where id=cid for update;
  flow_active=payroll_private.feature_enabled(cid,'salary_flow_v1');
  select * into flow_policy from payroll_private.salary_flow_policies where company_id=cid and effective_from<=month_start order by effective_from desc limit 1;
  if flow_active then
   if not payroll_private.feature_enabled(cid,'payroll_statement_v2') or not payroll_private.feature_enabled(cid,'payroll_statement_v3') then raise exception 'Enable statement v2 and v3 before company salary flow';end if;
   if flow_policy.company_id is null then raise exception 'Enter company DA and HRA percentages for this salary month first';end if;
  elsif flow_policy.company_id is not null or exists(select 1 from payroll_private.monthly_salary_deductions where company_id=cid and month=month_start and special_allowance<>0) then raise exception 'Company salary policy exists; re-enable its version before recalculating';end if;
  
 if not coalesce((c.settings->>'statutory_reviewed')::boolean,false) then raise exception 'Accountant must review statutory settings before payroll calculation';end if;
 if month_start<>date_trunc('month',month_start)::date then raise exception 'Select a month';end if;
 if (c.settings->>'effective_from')::date>month_start then raise exception 'These statutory settings do not cover that payroll month';end if;
 last_day=(month_start+interval '1 month - 1 day')::date;ndays=extract(day from last_day);
 remaining=case when extract(month from month_start)>=4 then 16-extract(month from month_start)::int else 4-extract(month from month_start)::int end;
 select id into rid from public.payroll_runs where company_id=cid and month=month_start for update;
 if rid is not null then
  if exists(select 1 from public.payroll_runs where id=rid and status not in ('calculated','hr_reviewed','accountant_reviewed')) then raise exception 'Locked payroll cannot be recalculated';end if;
  delete from public.payroll_lines where run_id=rid;
  update public.payroll_runs set status='calculated',created_by=auth.uid(),hr_by=null,accountant_by=null,authorized_by=null,input_hash=payroll_private.fingerprint(cid),snapshot=to_jsonb(c) where id=rid;
 else insert into public.payroll_runs(company_id,month,created_by,input_hash,snapshot) values(cid,month_start,auth.uid(),payroll_private.fingerprint(cid),to_jsonb(c)) returning id into rid;end if;
 for s in select * from public.payroll_staff where company_id=cid and joining_date<=last_day and (leaving_date is null or leaving_date>=month_start) loop
  select * into p from public.payroll_profiles where staff_id=s.id;
  deposit_base=0;deposit_all=true;component_hod=0;consolidated=0;consolidated_days=0;cca=0;hod=0;b=0;da=0;hra=0;other=0;lop=0;paid=0;issues='[]';
  late_plan=payroll_private.late_plan(s.id,month_start);
  select * into late_review from public.payroll_late_reviews where staff_id=s.id and month=month_start and status='active';
  late_valid=found and late_review.source_hash=late_plan->>'source_hash';
  if late_review.id is not null and not late_valid then issues=issues||jsonb_build_array('Late review inputs changed; reopen and review this month');
  elsif not late_valid and exists(select 1 from jsonb_array_elements(late_plan->'events') e where not (e->>'covered')::boolean) then issues=issues||jsonb_build_array('Principal / HR monthly late decision required');end if;
  for day in select generate_series(greatest(month_start,s.joining_date),least(last_day,coalesce(s.leaving_date,last_day)),interval '1 day')::date loop
   select * into sal from public.payroll_salaries where staff_id=s.id and effective_from<=day order by effective_from desc limit 1;
   if not found then issues=issues||jsonb_build_array('No salary version for '||day);continue;end if;
   is_work=(case when coalesce((c.settings->>'department_holidays_enabled')::boolean,false) then payroll_private.working_day(cid,s.id,day) else ((c.settings->'working_days') @> jsonb_build_array(extract(isodow from day)::int) and not (c.settings->'holidays') @> jsonb_build_array(day::text)) end);
   select l.* into lr from public.payroll_leaves l where l.staff_id=s.id and status='approved' and day between from_date and to_date limit 1;
   units=1;
   if found and is_work then
    select pol.paid into lrpaid from public.payroll_leave_policies pol where pol.company_id=cid and pol.code=lr.leave_type;
    if not lrpaid then
     units=case when lr.half_day then 0.5 else 0 end;
     if lr.half_day then
      select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
      if not found then issues=issues||jsonb_build_array('Review remaining half-day: '||day);
      elsif att.status='absent' then units=0;end if;
     end if;
    elsif lr.half_day then
     select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
     if not found then issues=issues||jsonb_build_array('Review remaining half-day: '||day);
     elsif att.status='absent' then units=0.5;end if;
    end if;
   elsif is_work then
    select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
    if not found then issues=issues||jsonb_build_array('Attendance not reviewed: '||day);
    elsif att.status='absent' then units=0;
    elsif att.status='half_day' then units=0.5;end if;
   end if;
   if late_valid then
    select coalesce(sum(0.5),0) into late_lop from jsonb_array_elements(late_review.decisions) d join public.payroll_attendance a on a.id=(d->>'attendance_id')::uuid where a.work_date=day and d->>'decision'='lop';
    units=greatest(0,units-late_lop);
   end if;
   if flow_active and sal.salary_mode<>'consolidated' then sal.da=round(sal.basic*flow_policy.da_rate/100,2);sal.hra=round(sal.basic*flow_policy.hra_rate/100,2);end if; factor=units/ndays;paid=paid+units;lop=lop+(1-units);
   if coalesce(sal.deposit_eligible_override,p.deposit_eligible,false) then deposit_base=deposit_base+(sal.basic+sal.da+sal.hra+sal.cca+sal.other+sal.hod_allowance)*factor;else deposit_all=false;end if;
   b=b+sal.basic*factor;da=da+sal.da*factor;hra=hra+sal.hra*factor;if sal.salary_mode='consolidated' then consolidated=consolidated+sal.other*factor;consolidated_days=consolidated_days+1;else other=other+sal.other*factor;end if;cca=cca+sal.cca*factor;hod=hod+sal.hod_allowance*factor;if sal.salary_mode<>'consolidated' then component_hod=component_hod+sal.hod_allowance*factor;end if;
  end loop;
  b=round(b,2);da=round(da,2);hra=round(hra,2);other=round(other,2);cca=round(cca,2);hod=round(hod,2);consolidated=round(consolidated,2);gross=b+da+hra+cca+other+hod+consolidated;
  
  flow_special=0;
  if flow_active then
   da=round(b*flow_policy.da_rate/100,2);hra=round(b*flow_policy.hra_rate/100,2);
   flow_gross=b+da+hra+cca+other+hod+consolidated;
   select coalesce((select special_allowance from payroll_private.monthly_salary_deductions where company_id=cid and staff_id=s.id and month=month_start),0) into flow_special;
   gross=flow_gross+flow_special;
   deposit_base=case when deposit_all then flow_gross else round(deposit_base,2) end;
  else deposit_base=case when deposit_all then gross else round(deposit_base,2) end;end if;
  
  -- Reviewed statutory wage model: Basic+DA plus exclusion add-back. Employer must confirm suitability.
  wage=greatest(b+da,gross/2);stat_wage=greatest(b+da,(b+da+hra+cca+other+round(component_hod,2))/2);
  pf=case when p.pf_enabled then case when flow_active then least(1800,round((b+da)*0.12,2)) else round(least(stat_wage,(c.settings->>'pf_cap')::numeric)*(c.settings->>'pf_rate')::numeric/100) end else 0 end;
  esi=case when p.esi_enabled then ceil(stat_wage*(c.settings->>'esi_rate')::numeric/100) else 0 end;
  tds=round(greatest(0,p.annual_tax-p.tax_paid)/remaining,2);
  select coalesce(sum(amount),0) into balance from public.payroll_deposits where staff_id=s.id;
  deposit=case when coalesce((c.settings->>'deposit_enabled')::boolean,false) then round(least(deposit_base*0.10,greatest(0,(c.settings->>'deposit_cap')::numeric-balance)),2) else 0 end;
  monthly_pt=coalesce((select v.pt_override from public.payroll_salaries v where v.staff_id=s.id and v.effective_from<=least(last_day,coalesce(s.leaving_date,last_day)) order by v.effective_from desc limit 1),case when coalesce((c.settings->>'pt_auto_slabs')::boolean,false) and month_start>=nullif(c.settings->>'pt_effective_from','')::date then payroll_private.pt_slab(gross) else p.pt end,0);
  
  manual_deductions='{}'::jsonb;
  if exists(select 1 from payroll_private.monthly_salary_deductions where company_id=cid and staff_id=s.id and month=month_start) then
   if not payroll_private.feature_enabled(cid,'payroll_statement_v3') or not payroll_private.feature_enabled(cid,'payroll_statement_v2') then raise exception 'Monthly deductions exist; re-enable the reviewed statement version before recalculating';end if;
   select jsonb_build_object('Installment',installment,'Advances',advances,'Welfare fund',welfare) into manual_deductions from payroll_private.monthly_salary_deductions where company_id=cid and staff_id=s.id and month=month_start;
  end if;
  deductions=pf+esi+tds+deposit+coalesce(p.other_deductions,0)+monthly_pt+coalesce((manual_deductions->>'Installment')::numeric,0)+coalesce((manual_deductions->>'Advances')::numeric,0)+coalesce((manual_deductions->>'Welfare fund')::numeric,0);
  
  if deductions>wage/2 then issues=issues||jsonb_build_array('Deductions exceed the conservative 50% reviewed-wage limit');end if;
  if deductions>gross then issues=issues||jsonb_build_array('Negative net pay');end if;
  insert into public.payroll_lines(staff_snapshot,deposit_opening,deposit_closing,company_id,run_id,staff_id,earnings,deductions,employer,gross,net,paid_days,lop,issues)
  values(to_jsonb(s)||case when flow_active then jsonb_build_object('salary_flow_v1',to_jsonb(flow_policy)) else '{}'::jsonb end,balance,balance+deposit,cid,rid,s.id,(case when consolidated_days=0 or b+da+hra+cca+other>0 then jsonb_build_object('Basic',b,'DA',da,'HRA',hra,'CCA',cca,'Allowances',other) else '{}'::jsonb end)||(case when hod>0 or consolidated_days=0 then jsonb_build_object('HOD/Coordinator Allowances',hod) else '{}'::jsonb end)||(case when consolidated_days>0 then jsonb_build_object('Consolidated salary',consolidated) else '{}'::jsonb end)||case when flow_active then jsonb_build_object('Special Allowance',flow_special) else '{}'::jsonb end,
  jsonb_build_object('PF',pf,'ESI',esi,'TDS',tds,'Security deposit',deposit,'Other deduction',coalesce(p.other_deductions,0),'PT',monthly_pt)||manual_deductions,
  jsonb_build_object('PF total',case when p.pf_enabled then case when flow_active then least(1800,round((b+da)*0.12,2)) else round(least(stat_wage,(c.settings->>'pf_cap')::numeric)*(c.settings->>'pf_employer_rate')::numeric/100) end else 0 end,'ESI',case when p.esi_enabled then ceil(stat_wage*(c.settings->>'esi_employer_rate')::numeric/100) else 0 end),gross,gross-deductions,paid,lop,issues);
  update public.payroll_lines set late_summary=late_plan-'events'-'source_hash'||jsonb_build_object('review_id',late_review.id,'review_valid',late_valid,'cl_days',case when late_valid then late_review.cl_units else 0 end,'lop_days',case when late_valid then (select count(*)*0.5 from jsonb_array_elements(late_review.decisions) d where d->>'decision'='lop') else 0 end) where run_id=rid and staff_id=s.id;
 end loop;
 if not exists(select 1 from public.payroll_lines where run_id=rid) then raise exception 'Add staff and salary details first';end if;
 return rid;
end$function$
;

CREATE OR REPLACE FUNCTION payroll_private.late_plan(sid uuid, m date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.payroll_staff;c public.payroll_companies;a record;remaining int=1500;used int=0;total int=0;uncovered int=0;events jsonb='[]';h text;
begin
 if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a payroll month';end if;
 select * into s from public.payroll_staff where id=sid;if not found then raise exception 'Staff not found';end if;
 select * into c from public.payroll_companies where id=s.company_id;
 for a in select at.id,at.work_date,to_char(at.in_time,'HH24:MI:SS') as in_time,coalesce(at.shift_snapshot->>'start',to_char(s.shift_start,'HH24:MI:SS')) as reporting_time,coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60) as mins from public.payroll_attendance at
 where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date
 and at.work_date>=s.joining_date and at.work_date<=coalesce(s.leaving_date,'infinity'::date) and at.status='present'
 and coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60)>0
 and (case when coalesce((c.settings->>'department_holidays_enabled')::boolean,false) then payroll_private.working_day(s.company_id,s.id,at.work_date) else (c.settings->'working_days' @> jsonb_build_array(extract(isodow from at.work_date)::int) and not c.settings->'holidays' @> jsonb_build_array(at.work_date::text)) end)
 and not exists(select 1 from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and at.work_date between l.from_date and l.to_date)
 order by coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60),at.work_date,at.id loop
  total=total+a.mins;
  if a.mins<=remaining then remaining=remaining-a.mins;used=used+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'seconds',a.mins,'cumulative_seconds',total,'minutes',a.mins::numeric/60,'cumulative_minutes',total::numeric/60,'covered',true));
  else uncovered=uncovered+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'seconds',a.mins,'cumulative_seconds',total,'minutes',a.mins::numeric/60,'cumulative_minutes',total::numeric/60,'covered',false));
  end if;
 end loop;
 h=md5(jsonb_build_array(m,25,s.id,s.joining_date,s.leaving_date,c.settings->'working_days',c.settings->'holidays',
 (select jsonb_agg(to_jsonb(at) order by at.work_date,at.id) from public.payroll_attendance at where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date),
 (select jsonb_agg(jsonb_build_array(l.id,l.from_date,l.to_date,l.half_day,l.leave_type) order by l.id) from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and l.to_date>=m and l.from_date<(m+interval '1 month')::date))::text);
 if payroll_private.holiday_signature(s.company_id,s.id,m,(m+interval '1 month - 1 day')::date) is not null then h=md5(h||payroll_private.holiday_signature(s.company_id,s.id,m,(m+interval '1 month - 1 day')::date));end if;
 return jsonb_build_object('month',m,'allowance',25,'allowance_seconds',1500,'total_seconds',total,'used_seconds',used,'unused_seconds',remaining,'uncovered_seconds',uncovered,'total_minutes',total::numeric/60,'used_minutes',used::numeric/60,'unused_minutes',remaining::numeric/60,'net_excess_minutes',greatest(0,total-1500)::numeric/60,'uncovered_minutes',uncovered::numeric/60,'events',events,'source_hash',h);
end$function$
;

CREATE OR REPLACE FUNCTION payroll_private.attendance_register_rows(cid uuid, m date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with raw as (
  select p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date work_date,
   jsonb_agg(jsonb_build_object('time',to_char(p.event_time at time zone 'Asia/Kolkata','HH24:MI:SS'),'direction',p.direction,'manual_entry',p.manual_entry) order by p.event_time,p.direction,p.id) punches
  from public.payroll_punches p where p.company_id=cid and p.event_time>=m::timestamp at time zone 'Asia/Kolkata'
   and p.event_time<(m+interval '1 month') at time zone 'Asia/Kolkata' group by p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date
 ),days as materialized (
  select s.id staff_id,s.name,s.code,s.department,s.shift_start,s.shift_end,s.early_grace,d::date work_date,
   (case when coalesce((c.settings->>'department_holidays_enabled')::boolean,false) then payroll_private.working_day(cid,s.id,d::date) else (c.settings->'working_days' @> jsonb_build_array(extract(isodow from d)::int) and not c.settings->'holidays' @> jsonb_build_array(d::date::text)) end) working_day,
   to_jsonb(a) attendance,coalesce(raw.punches,'[]'::jsonb) punches,
   case when a.id is null then raw.punches is null else
    (a.punch_hash is not distinct from payroll_private.day_punch_hash(cid,s.id,d::date) or (a.punch_hash is null and raw.punches is null))
    and (a.review_context_hash is null or a.review_context_hash=payroll_private.attendance_context_hash(cid,s.id)) end evidence_current,
   (select jsonb_agg(jsonb_build_object('type',l.leave_type,'half_day',l.half_day,'paid',pol.paid)) from public.payroll_leaves l join public.payroll_leave_policies pol on pol.company_id=l.company_id and pol.code=l.leave_type where l.company_id=cid and l.staff_id=s.id and l.status='approved' and d::date between l.from_date and l.to_date) leaves,
   (select coalesce(sum(0.5),0) from public.payroll_late_reviews lr cross join jsonb_array_elements(lr.decisions) dec join public.payroll_attendance la on la.id=(dec->>'attendance_id')::uuid where lr.company_id=cid and lr.staff_id=s.id and lr.month=m and lr.status='active' and la.work_date=d::date and dec->>'decision'='lop') late_lop
  from public.payroll_staff s join public.payroll_companies c on c.id=s.company_id
  cross join lateral generate_series(greatest(m,s.joining_date),least((m+interval '1 month - 1 day')::date,coalesce(s.leaving_date,'infinity'::date)),interval '1 day') d
  left join public.payroll_attendance a on a.company_id=cid and a.staff_id=s.id and a.work_date=d::date
  left join raw on raw.staff_id=s.id and raw.work_date=d::date
  where s.company_id=cid and s.joining_date<(m+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>=m
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
$function$
;

CREATE OR REPLACE FUNCTION payroll_private.attendance_period_hash(cid uuid, m date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with original(value) as materialized (select md5(jsonb_build_array(
  (select jsonb_build_array(settings->'working_days',settings->'holidays') from public.payroll_companies where id=cid),
  (select jsonb_agg(to_jsonb(s)-'leave_balances' order by s.id) from public.payroll_staff s where company_id=cid and joining_date<(m+interval '1 month')::date and coalesce(leaving_date,'infinity'::date)>=m),
  (select jsonb_agg(to_jsonb(a) order by a.staff_id,a.work_date) from public.payroll_attendance a where company_id=cid and work_date>=m and work_date<(m+interval '1 month')::date),
  (select jsonb_agg(to_jsonb(p) order by p.staff_id,p.event_time,p.id) from public.payroll_punches p where company_id=cid and event_time>=m::timestamp at time zone 'Asia/Kolkata' and event_time<(m+interval '1 month') at time zone 'Asia/Kolkata'),
  (select jsonb_agg(to_jsonb(l) order by l.id) from public.payroll_leaves l where company_id=cid and from_date<(m+interval '1 month')::date and to_date>=m),
  (select jsonb_agg(to_jsonb(p) order by p.code) from public.payroll_leave_policies p where company_id=cid),
  (select jsonb_agg(to_jsonb(r) order by r.id) from public.payroll_late_reviews r where company_id=cid and month=m)
 )::text)) select case when payroll_private.holiday_signature(cid,null,m,(m+interval '1 month - 1 day')::date) is null then value else md5(value||payroll_private.holiday_signature(cid,null,m,(m+interval '1 month - 1 day')::date)) end from original
$function$
;

CREATE OR REPLACE FUNCTION payroll_private.fingerprint(cid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with original(value) as materialized (select case when exists(select 1 from payroll_private.salary_flow_policies where company_id=cid) then md5((select case when exists(select 1 from payroll_private.monthly_salary_deductions where company_id=cid) then md5((
 select md5(jsonb_build_array(
 (select to_jsonb(c) from public.payroll_companies c where id=cid),
 (select jsonb_agg(s order by id) from public.payroll_staff s where company_id=cid),
 (select jsonb_agg(p order by staff_id) from public.payroll_profiles p where company_id=cid),
 (select jsonb_agg(s order by id) from public.payroll_salaries s where company_id=cid),
 (select jsonb_agg(a order by id) from public.payroll_attendance a where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_leaves l where company_id=cid),
 (select jsonb_agg(d order by id) from public.payroll_deposits d where company_id=cid),
 (select jsonb_agg(p order by code) from public.payroll_leave_policies p where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_late_reviews l where company_id=cid))::text)
)||(select jsonb_agg(d order by month,staff_id)::text from payroll_private.monthly_salary_deductions d where company_id=cid)) else (
 select md5(jsonb_build_array(
 (select to_jsonb(c) from public.payroll_companies c where id=cid),
 (select jsonb_agg(s order by id) from public.payroll_staff s where company_id=cid),
 (select jsonb_agg(p order by staff_id) from public.payroll_profiles p where company_id=cid),
 (select jsonb_agg(s order by id) from public.payroll_salaries s where company_id=cid),
 (select jsonb_agg(a order by id) from public.payroll_attendance a where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_leaves l where company_id=cid),
 (select jsonb_agg(d order by id) from public.payroll_deposits d where company_id=cid),
 (select jsonb_agg(p order by code) from public.payroll_leave_policies p where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_late_reviews l where company_id=cid))::text)
) end)||(select jsonb_agg(p order by effective_from)::text from payroll_private.salary_flow_policies p where company_id=cid)) else (select case when exists(select 1 from payroll_private.monthly_salary_deductions where company_id=cid) then md5((
 select md5(jsonb_build_array(
 (select to_jsonb(c) from public.payroll_companies c where id=cid),
 (select jsonb_agg(s order by id) from public.payroll_staff s where company_id=cid),
 (select jsonb_agg(p order by staff_id) from public.payroll_profiles p where company_id=cid),
 (select jsonb_agg(s order by id) from public.payroll_salaries s where company_id=cid),
 (select jsonb_agg(a order by id) from public.payroll_attendance a where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_leaves l where company_id=cid),
 (select jsonb_agg(d order by id) from public.payroll_deposits d where company_id=cid),
 (select jsonb_agg(p order by code) from public.payroll_leave_policies p where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_late_reviews l where company_id=cid))::text)
)||(select jsonb_agg(d order by month,staff_id)::text from payroll_private.monthly_salary_deductions d where company_id=cid)) else (
 select md5(jsonb_build_array(
 (select to_jsonb(c) from public.payroll_companies c where id=cid),
 (select jsonb_agg(s order by id) from public.payroll_staff s where company_id=cid),
 (select jsonb_agg(p order by staff_id) from public.payroll_profiles p where company_id=cid),
 (select jsonb_agg(s order by id) from public.payroll_salaries s where company_id=cid),
 (select jsonb_agg(a order by id) from public.payroll_attendance a where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_leaves l where company_id=cid),
 (select jsonb_agg(d order by id) from public.payroll_deposits d where company_id=cid),
 (select jsonb_agg(p order by code) from public.payroll_leave_policies p where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_late_reviews l where company_id=cid))::text)
) end) end) select case when payroll_private.holiday_signature(cid) is null then value else md5(value||payroll_private.holiday_signature(cid)) end from original
$function$
;
notify pgrst, 'reload schema';
