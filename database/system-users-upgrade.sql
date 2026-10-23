-- Company software users are independent of employee/payroll records.
create table payroll_private.system_users(
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.payroll_companies,
 username text not null unique check(username ~ '^[a-z0-9]+(\.[a-z0-9]+)*$' and length(username)<=64),
 name text not null check(length(trim(name)) between 2 and 120),
 requested_role text not null check(requested_role in ('admin','hr','accountant','manager','director','principal','president')),
 user_id uuid unique references auth.users,created_by uuid not null references auth.users,created_at timestamptz not null default now()
);
alter table payroll_private.system_users enable row level security;
revoke all on payroll_private.system_users from public,anon,authenticated;

create or replace function payroll_private.staff_login_name(n text,c text) returns text language plpgsql security definer set search_path='' as $$
declare base text;candidate text;i integer=1;
begin
 base=left(trim(both '.' from regexp_replace(lower(coalesce(n,'')),'[^a-z0-9]+','.','g')),48);if base='' then base='staff';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('payroll-login-global'));
 candidate=base;
 while exists(select 1 from public.payroll_staff where lower(login_name)=candidate)
    or exists(select 1 from payroll_private.system_users where username=candidate)
    or exists(select 1 from auth.users where lower(email)=candidate||'@staff.payroll.invalid') loop
  i=i+1;candidate=base||'.'||i::text;
 end loop;return candidate;
end$$;

create function payroll_private.system_user_staff_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('payroll-login-global'));
 if exists(select 1 from payroll_private.system_users s where s.user_id=new.user_id or lower(new.email)=s.username||'@staff.payroll.invalid') then
  raise exception 'This login is a system user, not an employee. Use a separate employee login.';
 end if;return new;
end$$;
revoke all on function payroll_private.system_user_staff_guard() from public,anon,authenticated;
create trigger payroll_system_user_staff_guard before insert or update of email,user_id on public.payroll_staff for each row execute function payroll_private.system_user_staff_guard();

create function payroll_private.system_users_api(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid();cid uuid=nullif(payload->>'company_id','')::uuid;op text=payload->>'action';
 uname text=lower(trim(payload->>'username'));display_name text=trim(payload->>'name');selected_role text=payload->>'role';
 s payroll_private.system_users;account auth.users;target uuid;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed sign-in required';end if;
 if op='password_ready' then
  if not exists(select 1 from payroll_private.system_users p join auth.users u on u.id=p.user_id join public.payroll_members m on m.company_id=p.company_id and m.user_id=u.id
   where u.id=uid and u.raw_app_meta_data->>'payroll_system_user_id'=p.id::text and u.raw_app_meta_data->>'payroll_company_id'=p.company_id::text and m.role<>'staff') then raise exception 'System user setup must finish before password change';end if;
  return jsonb_build_object('ready',true);
 end if;
 if payroll_private.role(cid) is distinct from 'admin' then raise exception 'Full company access required';end if;
 if op='list' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'name',p.name,'role',coalesce(m.role,p.requested_role),'status',case when p.user_id is null then 'pending' else 'active' end) order by p.username) from payroll_private.system_users p left join public.payroll_members m on m.company_id=p.company_id and m.user_id=p.user_id where p.company_id=cid),'[]'::jsonb);
 end if;
 perform 1 from public.payroll_companies where id=cid for update;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('payroll-login-global'));
 if op='prepare' then
  if uname is null or uname !~ '^[a-z0-9]+(\.[a-z0-9]+)*$' or length(uname)>64 then raise exception 'Use a username such as testing.admin: lowercase letters, numbers and dots, up to 64 characters';end if;
  if display_name is null or length(display_name) not between 2 and 120 then raise exception 'Enter a name (2–120 characters)';end if;
  if selected_role is null or selected_role not in ('admin','hr','accountant','manager','director','principal','president') then raise exception 'Choose a system role; employee self-service requires Staff Master';end if;
  select * into s from payroll_private.system_users where username=uname for update;
  if found and (s.company_id<>cid or s.requested_role<>selected_role or s.name<>display_name) then raise exception 'Username is unavailable or already reserved with different details';end if;
  if s.id is null then
   if exists(select 1 from public.payroll_staff where lower(login_name)=uname or lower(email)=uname||'@staff.payroll.invalid') or exists(select 1 from auth.users where lower(email)=uname||'@staff.payroll.invalid') then raise exception 'Username is unavailable; choose another';end if;
   insert into payroll_private.system_users(company_id,username,name,requested_role,created_by) values(cid,uname,display_name,selected_role,uid) returning * into s;
  end if;
  if s.user_id is not null then return jsonb_build_object('id',s.id,'username',s.username,'linked',true);end if;
  select * into account from auth.users where lower(email)=s.username||'@staff.payroll.invalid';
  if account.id is not null and (account.raw_app_meta_data->>'payroll_system_user_id' is distinct from s.id::text or account.raw_app_meta_data->>'payroll_company_id' is distinct from cid::text) then raise exception 'Username belongs to another account';end if;
  return jsonb_build_object('id',s.id,'username',s.username,'email',s.username||'@staff.payroll.invalid','linked',false,'pending_user_id',account.id);
 elsif op='link' then
  select * into s from payroll_private.system_users where id=(payload->>'id')::uuid and company_id=cid for update;if not found then raise exception 'System user reservation not found in this company';end if;
  target=(payload->>'user_id')::uuid;
  if s.user_id is not null then
   if s.user_id is distinct from target then raise exception 'System user already linked';end if;return jsonb_build_object('ok',true);
  end if;
  if not exists(select 1 from auth.users u where u.id=target and lower(u.email)=s.username||'@staff.payroll.invalid' and u.email_confirmed_at is not null
   and u.raw_app_meta_data->>'payroll_system_user_id'=s.id::text and u.raw_app_meta_data->>'payroll_company_id'=cid::text
   and coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Account was not provisioned for this system user';end if;
  if exists(select 1 from public.payroll_staff where user_id=target) or exists(select 1 from public.payroll_members where user_id=target) then raise exception 'Account already has a company or employee association';end if;
  insert into public.payroll_members(company_id,user_id,role) values(cid,target,s.requested_role);
  update payroll_private.system_users set user_id=target where id=s.id;
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'system_user_created',s.id::text);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Unknown system user action';
end$$;
revoke all on function payroll_private.system_users_api(jsonb) from public,anon;
grant execute on function payroll_private.system_users_api(jsonb) to authenticated;
create function public.payroll_system_users(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.system_users_api(payload)$$;
revoke all on function public.payroll_system_users(jsonb) from public,anon;
grant execute on function public.payroll_system_users(jsonb) to authenticated;
notify pgrst,'reload schema';
