-- Repairs existing installations without replaying table-creating upgrades.
-- Deploy only after system-users-upgrade.sql and salary-payment-holds-upgrade.sql.
do $$begin
 if to_regclass('payroll_private.system_users') is null or to_regclass('payroll_private.salary_payment_holds') is null then
  raise exception 'Install system users and salary payment holds before the reliability migration';
 end if;
end$$;

create or replace function payroll_private.payment_dispatch(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=nullif(payload->>'company_id','')::uuid;uid uuid=auth.uid();sid uuid=nullif(payload->>'staff_id','')::uuid;
 rid uuid=nullif(payload->>'id','')::uuid;r text;m date;out jsonb;req uuid=nullif(payload->>'request_id','')::uuid;
 h payroll_private.salary_payment_holds;run public.payroll_runs;ln public.payroll_lines;previous_revision integer;changed integer;
begin
 if action='bootstrap' then
  out=payroll_private.dispatch(action,payload);
  if to_regclass('public.payroll_platform_admins') is not null then
   select out||jsonb_build_object('companies',coalesce(jsonb_agg(j||jsonb_build_object('platform_status',c.platform_status,'enabled_modules',c.enabled_modules)),'[]'::jsonb))
    into out from jsonb_array_elements(out->'companies') j join public.payroll_companies c on c.id=(j->>'id')::uuid;
   return out;
  end if;
  return out;
 end if;
 if action='state' then
  out=payroll_private.dispatch(action,payload);r=payroll_private.role(cid);
  if r in ('admin','accountant','hr') then
   out=out||jsonb_build_object('salary_holds',coalesce((select jsonb_agg(t order by month desc,staff_id) from payroll_private.salary_payment_holds t where company_id=cid),'[]'::jsonb));
  end if;return out;
 end if;
 if action not in ('salary_hold_set','salary_payment_state','salary_hold_history') and not(action='payroll_decide' and payload->>'decision'='paid') then return payroll_private.dispatch(action,payload);end if;
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed authentication required';end if;
 r=payroll_private.role(cid);if r is null or r not in ('admin','accountant','hr') then raise exception 'Authorized company access required';end if;
 if r='hr' and (action='salary_payment_state' or action='payroll_decide') then raise exception 'Accounts access required';end if;
 -- Same company lock order as payroll calculation, approvals and other writes.
 perform 1 from public.payroll_companies where id=cid for update;
 if action='salary_hold_history' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Choose a calendar month';end if;
  return coalesce((select jsonb_agg(e order by id desc) from payroll_private.salary_payment_hold_events e where company_id=cid and month=m),'[]'::jsonb);
 end if;
 if action='salary_payment_state' then
  select * into run from public.payroll_runs where id=rid and company_id=cid;if not found then raise exception 'Payroll not found';end if;
  if run.status<>'released' then raise exception 'Release payroll before preparing bank payments';end if;
  return jsonb_build_object('held_count',(select count(*) from public.payroll_lines l join payroll_private.salary_payment_holds ph on ph.company_id=l.company_id and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held' where l.run_id=rid),
   'paid_count',(select count(*) from public.payroll_lines where run_id=rid and payment_reference is not null),
   'rows',coalesce((select jsonb_agg(jsonb_build_object('staff_id',l.staff_id,'name',s.name,'bank_account',p.bank_account,'ifsc',p.ifsc,'net',l.net) order by s.code,l.staff_id) from public.payroll_lines l join public.payroll_staff s on s.id=l.staff_id left join public.payroll_profiles p on p.staff_id=l.staff_id where l.run_id=rid and l.payment_reference is null and not exists(select 1 from payroll_private.salary_payment_holds ph where ph.company_id=cid and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held')),'[]'::jsonb));
 end if;
 if action='salary_hold_set' and (r not in ('admin','hr','accountant') or (r<>'admin' and payload->>'status' is distinct from 'held')) then raise exception 'HR or Accountant may hold payment; only Administrator, Principal or President may release';end if;
 if req is null then raise exception 'Request ID required';end if;
 select response into out from payroll_private.requests where token=req and company_id=cid and user_id=uid and operation=action and request_hash=md5(payload::text);
 if found then return out;end if;
 if exists(select 1 from payroll_private.requests where token=req) then raise exception 'Request ID reused with different data';end if;
 if action='salary_hold_set' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Choose a calendar month';end if;
  if coalesce(payload->>'status','') not in ('held','released') or length(trim(coalesce(payload->>'reason',''))) not between 5 and 1000 then raise exception 'Choose hold or release and enter a reason (5–1000 characters)';end if;
  if not exists(select 1 from public.payroll_staff where id=sid and company_id=cid) then raise exception 'Staff not found in this company';end if;
  select * into run from public.payroll_runs where company_id=cid and month=m for update;
  select * into ln from public.payroll_lines where run_id=run.id and staff_id=sid and company_id=cid for update;
  if run.status='paid' or ln.payment_reference is not null then raise exception 'Payment is already reconciled; a hold cannot change a paid salary';end if;
  select * into h from payroll_private.salary_payment_holds where company_id=cid and staff_id=sid and month=m for update;
  previous_revision=coalesce(h.revision,0);
  if nullif(payload->>'expected_revision','')::integer is distinct from previous_revision then raise exception 'Hold changed; reload before saving';end if;
  if h.status is not distinct from payload->>'status' or (payload->>'status'='released' and h.status is distinct from 'held') then raise exception 'Hold state changed; reload before saving';end if;
  insert into payroll_private.salary_payment_holds(company_id,staff_id,month,status,revision,reason,updated_by) values(cid,sid,m,payload->>'status',previous_revision+1,trim(payload->>'reason'),uid)
   on conflict(company_id,staff_id,month) do update set status=excluded.status,revision=excluded.revision,reason=excluded.reason,updated_by=uid,updated_at=now() returning * into h;
  insert into payroll_private.salary_payment_hold_events(company_id,staff_id,month,revision,status,reason,actor) values(cid,sid,m,h.revision,h.status,h.reason,uid);
  out=to_jsonb(h);
 else
  select * into run from public.payroll_runs where id=rid and company_id=cid for update;if not found then raise exception 'Payroll not found';end if;
  if run.status<>'released' or length(trim(coalesce(payload->>'payment_reference','')))<5 then raise exception 'Release payslips first and provide reconciled payment evidence';end if;
  update public.payroll_lines l set payment_reference=trim(payload->>'payment_reference') where l.run_id=rid and l.payment_reference is null and not exists(select 1 from payroll_private.salary_payment_holds ph where ph.company_id=cid and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held');
  get diagnostics changed=row_count;
  if changed=0 then raise exception 'No unpaid, unheld salaries to reconcile';end if;
  if not exists(select 1 from public.payroll_lines where run_id=rid and payment_reference is null) then update public.payroll_runs set status='paid' where id=rid;end if;
  out=jsonb_build_object('id',rid,'ok',true,'reconciled_staff',changed,'remaining_unpaid',(select count(*) from public.payroll_lines where run_id=rid and payment_reference is null));
 end if;
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,action,coalesce(sid,rid)::text);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(req,cid,uid,action,md5(payload::text),out);
 return out;
end$$;
revoke all on function payroll_private.payment_dispatch(text,jsonb) from public,anon;
grant execute on function payroll_private.payment_dispatch(text,jsonb) to authenticated;

-- Platform-level Payroll administration. This is additive and does not grant
-- platform access to existing company administrators.
create table if not exists public.payroll_platform_admins(
 user_id uuid primary key references auth.users on delete cascade,
 created_at timestamptz not null default now(),
 created_by uuid references auth.users
);
alter table public.payroll_platform_admins enable row level security;
revoke all on public.payroll_platform_admins from public,anon,authenticated;

alter table public.payroll_companies
 add column if not exists platform_status text not null default 'active'
   check(platform_status in ('active','paused')),
 add column if not exists enabled_modules jsonb not null default '{"staff":true,"attendance":true,"leave":true,"payroll":true,"letters":true,"assessments":true,"reports":true,"settings":true}',
 add column if not exists platform_revision integer not null default 0 check(platform_revision>=0);

create or replace function payroll_private.platform_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_platform_admins where user_id=auth.uid())
$$;
revoke all on function payroll_private.platform_admin() from public,anon,authenticated;
grant execute on function payroll_private.platform_admin() to authenticated;

create or replace function payroll_private.module_enabled(cid uuid,module text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_companies c where c.id=cid and c.platform_status='active' and coalesce((c.enabled_modules->>module)::boolean,false))
$$;
revoke all on function payroll_private.module_enabled(uuid,text) from public,anon,authenticated;
grant execute on function payroll_private.module_enabled(uuid,text) to authenticated;

create or replace function payroll_private.platform_admin_api(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); op text=payload->>'action'; cid uuid=nullif(payload->>'company_id','')::uuid;
  expected integer; next_modules jsonb; company public.payroll_companies; result jsonb;
begin
 if uid is null or not payroll_private.platform_admin() then raise exception 'Platform administrator access required'; end if;
 if op='snapshot' then
  return jsonb_build_object('companies',coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'address',c.address,'status',c.platform_status,
    'modules',c.enabled_modules,'revision',c.platform_revision,'created_at',c.created_at,
    'members',(select count(*) from public.payroll_members m where m.company_id=c.id),
    'staff',(select count(*) from public.payroll_staff s where s.company_id=c.id and s.status='active')
  ) order by c.created_at,c.id) from public.payroll_companies c),'[]'::jsonb));
 elsif op='create_company' then
  if length(trim(coalesce(payload->>'name',''))) not between 2 and 160 then raise exception 'Company name must be 2–160 characters'; end if;
  insert into public.payroll_companies(name,address,enabled_modules) values(trim(payload->>'name'),coalesce(payload->>'address',''),'{}'::jsonb) returning * into company;
  insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid) values(company.id,'CL',12,true),(company.id,'SL',12,true),(company.id,'EL',0,true),(company.id,'LWP',0,false);
  insert into public.payroll_audit(company_id,actor,action,record_id) values(company.id,uid,'platform_company_created',company.id::text);
  return jsonb_build_object('id',company.id,'name',company.name);
 elsif op='update_company' then
  select * into company from public.payroll_companies where id=cid for update; if not found then raise exception 'Company not found'; end if;
  expected=(payload->>'revision')::integer;
  if expected is distinct from company.platform_revision then raise exception 'Company access changed; reload before saving'; end if;
  if payload->>'status' not in ('active','paused') then raise exception 'Choose active or paused'; end if;
  next_modules=coalesce(payload->'modules','{}'::jsonb);
  if jsonb_typeof(next_modules)<>'object' or exists(select 1 from jsonb_object_keys(next_modules) k where k not in ('staff','attendance','leave','payroll','letters','assessments','reports','settings') or jsonb_typeof(next_modules->k)<>'boolean') then raise exception 'Invalid module access'; end if;
  update public.payroll_companies set platform_status=payload->>'status',enabled_modules=next_modules,platform_revision=platform_revision+1 where id=cid;
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'platform_company_access_updated',cid::text);
  return jsonb_build_object('ok',true,'revision',company.platform_revision+1);
 else raise exception 'Unknown platform administration action'; end if;
end$$;
revoke all on function payroll_private.platform_admin_api(jsonb) from public,anon;
grant execute on function payroll_private.platform_admin_api(jsonb) to authenticated;
create or replace function public.payroll_platform_admin(payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select payroll_private.platform_admin_api(payload)$$;
revoke all on function public.payroll_platform_admin(jsonb) from public,anon;
grant execute on function public.payroll_platform_admin(jsonb) to authenticated;

-- The account edge function uses this narrow RPC for platform-created company
-- administrators. Passwords never pass through SQL or appear in responses.
create or replace function payroll_private.platform_system_user_api(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); op text=payload->>'action'; cid uuid=nullif(payload->>'company_id','')::uuid;
  s payroll_private.system_users; target uuid; uname text=lower(trim(payload->>'username')); display_name text=trim(payload->>'name'); selected_role text=payload->>'role';
begin
 if uid is null or not payroll_private.platform_admin() then raise exception 'Platform administrator access required'; end if;
 if not exists(select 1 from public.payroll_companies where id=cid) then raise exception 'Company not found'; end if;
 if op='prepare' then
  if uname is null or uname !~ '^[a-z0-9]+(\.[a-z0-9]+)*$' or length(uname)>64 then raise exception 'Use a valid username'; end if;
  if display_name is null or length(display_name) not between 2 and 120 then raise exception 'Enter a name (2–120 characters)'; end if;
  if selected_role not in ('admin','hr','accountant','manager','director','principal','president') then raise exception 'Choose a valid company role'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('payroll-login-global'));
  select * into s from payroll_private.system_users where username=uname for update;
  if found and (s.company_id<>cid or s.requested_role<>selected_role or s.name<>display_name) then raise exception 'Username is unavailable or reserved with different details'; end if;
  if s.id is null then
   if exists(select 1 from public.payroll_staff where lower(login_name)=uname) or exists(select 1 from auth.users where lower(email)=uname||'@staff.payroll.invalid') then raise exception 'Username is unavailable'; end if;
   insert into payroll_private.system_users(company_id,username,name,requested_role,created_by) values(cid,uname,display_name,selected_role,uid) returning * into s;
  end if;
  if s.user_id is not null then return jsonb_build_object('id',s.id,'username',s.username,'linked',true); end if;
  select id into target from auth.users where lower(email)=s.username||'@staff.payroll.invalid';
  return jsonb_build_object('id',s.id,'username',s.username,'email',s.username||'@staff.payroll.invalid','linked',false,'pending_user_id',target);
 elsif op='link' then
  select * into s from payroll_private.system_users where id=(payload->>'id')::uuid and company_id=cid for update;
  if not found then raise exception 'System user reservation not found'; end if;
  target=(payload->>'user_id')::uuid;
  if s.user_id is not null then if s.user_id is distinct from target then raise exception 'System user already linked'; end if; return jsonb_build_object('ok',true); end if;
  if not exists(select 1 from auth.users u where u.id=target and lower(u.email)=s.username||'@staff.payroll.invalid' and u.email_confirmed_at is not null and u.raw_app_meta_data->>'payroll_system_user_id'=s.id::text and u.raw_app_meta_data->>'payroll_company_id'=cid::text and coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Account was not provisioned for this system user'; end if;
  if exists(select 1 from public.payroll_staff where user_id=target) or exists(select 1 from public.payroll_members where user_id=target) then raise exception 'Account already has a company or employee association'; end if;
  insert into public.payroll_members(company_id,user_id,role) values(cid,target,s.requested_role);
  update payroll_private.system_users set user_id=target where id=s.id;
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'platform_system_user_created',s.id::text);
  return jsonb_build_object('ok',true);
 else raise exception 'Unknown platform account action'; end if;
end$$;
revoke all on function payroll_private.platform_system_user_api(jsonb) from public,anon;
grant execute on function payroll_private.platform_system_user_api(jsonb) to authenticated;
create or replace function public.payroll_platform_user(payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select payroll_private.platform_system_user_api(payload)$$;
revoke all on function public.payroll_platform_user(jsonb) from public,anon;
grant execute on function public.payroll_platform_user(jsonb) to authenticated;

-- Company administrators keep their existing role, but writes now fail closed
-- when the platform has paused the company or disabled the relevant module.
create or replace function payroll_private.platform_action_module(action text) returns text
language sql immutable set search_path='' as $$
 select case
  when action in ('staff_save','staff_import','staff_roster_import','staff_delete','staff_login_prepare','staff_login_link','initial_salary','increment_save','increment_decide','service_change','separate','staff_activate') then 'staff'
  when action in ('attendance_save','attendance_report','punch_import','late_month','late_review','late_reopen') then 'attendance'
  when action like 'leave_%' then 'leave'
  when action like 'payroll_%' or action in ('tax_inputs','deposit_refund','salary_payment_state','salary_hold_set','salary_hold_history') then 'payroll'
  when action like 'document_%' then 'letters'
  when action like 'assessment_%' then 'assessments'
  when action in ('reports','deposit_balances','deposit_transactions') then 'reports'
  when action in ('settings','member_grant','company_create') then 'settings'
  else null end
$$;
create or replace function payroll_private.platform_action_guard(action text,payload jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare cid uuid=nullif(payload->>'company_id','')::uuid; module text;
begin
 if action in ('bootstrap','state','staff_password_ready') or payroll_private.platform_admin() then return true; end if;
 -- Serialize module checks with platform pause/update and the business write.
 perform 1 from public.payroll_companies where id=cid for update;
 module=payroll_private.platform_action_module(action);
 if module is not null and not payroll_private.module_enabled(cid,module) then raise exception 'This Payroll module is paused or unavailable for the company'; end if;
 return true;
end$$;
revoke all on function payroll_private.platform_action_guard(text,jsonb) from public,anon;
grant execute on function payroll_private.platform_action_guard(text,jsonb) to authenticated;

create or replace function payroll_private.platform_direct_guard(payload jsonb,module text) returns boolean
language plpgsql security definer set search_path='' as $$
declare cid uuid=nullif(payload->>'company_id','')::uuid;
begin
 if payroll_private.platform_admin() then return true;end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if payroll_private.module_enabled(cid,module) then return true; end if;
 raise exception 'This Payroll module is paused or unavailable for the company';
end$$;
revoke all on function payroll_private.platform_direct_guard(jsonb,text) from public,anon;
grant execute on function payroll_private.platform_direct_guard(jsonb,text) to authenticated;

create or replace function public.payroll_assign_shifts(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.assign_shifts(payload) from payroll_private.platform_direct_guard(payload,'attendance')$$;
create or replace function public.payroll_department_salaries(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.department_salaries(payload) from payroll_private.platform_direct_guard(payload,'payroll')$$;
create or replace function public.payroll_username_role(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.username_role(payload) from payroll_private.platform_direct_guard(payload,'settings')$$;
create or replace function public.payroll_bulk_leave_balances(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.bulk_leave_balances(payload) from payroll_private.platform_direct_guard(payload,'leave')$$;
create or replace function public.payroll_bulk_attendance(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.bulk_attendance(payload) from payroll_private.platform_direct_guard(payload,'attendance')$$;
-- Company system-user access is also a settings write. This replacement is
-- applied after system-users-upgrade.sql in an installed database.
create or replace function public.payroll_system_users(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.system_users_api(payload) from payroll_private.platform_direct_guard(payload,'settings')$$;

-- Preserve payment holds and reconciliation when adding platform controls.
create or replace function public.payroll_api(action text,payload jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 perform payroll_private.platform_action_guard(action,payload);
 return payroll_private.payment_dispatch(action,payload);
end
$$;
grant execute on function public.payroll_api(text,jsonb) to authenticated;
notify pgrst,'reload schema';
