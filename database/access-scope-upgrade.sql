-- Company access rules and reserved name-based login IDs. No Auth accounts/passwords are changed.
alter table public.payroll_members drop constraint payroll_members_role_check;
alter table public.payroll_members add constraint payroll_members_role_check check(role in ('admin','principal','president','director','hr','accountant','manager','staff'));
alter table public.payroll_staff add column login_name text;
create unique index payroll_staff_login_name_idx on public.payroll_staff(lower(login_name));
create function payroll_private.staff_login_name(n text,c text) returns text language plpgsql security definer set search_path='' as $$
declare base text;candidate text;i int=1;
begin
 base=left(trim(both '.' from regexp_replace(lower(coalesce(n,'')),'[^a-z0-9]+','.','g')),48);if base='' then base='staff';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('payroll-login:'||base));
 candidate=base;
 while exists(select 1 from public.payroll_staff where lower(login_name)=candidate) loop
  i=i+1;candidate=base||'.'||i::text;
 end loop;
 return candidate;
end$$;
create function payroll_private.set_staff_login_name() returns trigger language plpgsql security definer set search_path='' as $$
begin new.login_name=payroll_private.staff_login_name(new.name,new.code);return new;end$$;
revoke all on function payroll_private.staff_login_name(text,text),payroll_private.set_staff_login_name() from public,anon,authenticated;
do $$declare s record;begin for s in select id,name,code from public.payroll_staff where login_name is null order by company_id,code,id loop
 update public.payroll_staff set login_name=payroll_private.staff_login_name(s.name,s.code) where id=s.id;
end loop;end$$;
alter table public.payroll_staff alter column login_name set not null;
create trigger payroll_staff_login_name before insert on public.payroll_staff for each row execute function payroll_private.set_staff_login_name();
create or replace function payroll_private.role(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select case when m.role in ('admin','principal','president') or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office in ('principal','president')) then 'admin'
 when m.role='hr' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='hr') then 'hr' when m.role='director' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='director') then 'manager' else m.role end
 from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid()
 and not exists(select 1 from auth.users u where u.id=auth.uid() and coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false))
 and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='separated')
 and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='active'))
$$;
create function payroll_private.display_role(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select case when m.role in ('admin','principal','president','director') then m.role
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='principal') then 'principal'
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='president') then 'president'
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='director') then 'director' else payroll_private.role(cid) end from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid() and payroll_private.role(cid) is not null
$$;
create function payroll_private.staff_run_access(rid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_runs r join public.payroll_lines l on l.run_id=r.id where r.id=rid and r.status in ('released','paid') and payroll_private.own(l.staff_id))
$$;
revoke all on function payroll_private.display_role(uuid),payroll_private.staff_run_access(uuid) from public,anon,authenticated;
grant execute on function payroll_private.staff_run_access(uuid) to authenticated;
drop policy profiles_read on public.payroll_profiles;
create policy profiles_read on public.payroll_profiles for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant'));
drop policy salaries_read on public.payroll_salaries;
create policy salaries_read on public.payroll_salaries for select to authenticated using(payroll_private.role(company_id) in ('admin','accountant'));
drop policy attendance_read on public.payroll_attendance;
create policy attendance_read on public.payroll_attendance for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or (payroll_private.role(company_id)='manager' and payroll_private.team(staff_id)));
drop policy punches_read on public.payroll_punches;
create policy punches_read on public.payroll_punches for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant'));
drop policy documents_read on public.payroll_documents;
create policy documents_read on public.payroll_documents for select to authenticated using(payroll_private.role(company_id) in ('admin','hr'));
drop policy assessments_read on public.payroll_assessments;
create policy assessments_read on public.payroll_assessments for select to authenticated using(payroll_private.role(company_id)='admin' or (payroll_private.role(company_id)='manager' and payroll_private.team(staff_id)));
drop policy increments_read on public.payroll_increments;
create policy increments_read on public.payroll_increments for select to authenticated using(payroll_private.role(company_id) in ('admin','accountant'));
drop policy runs_read on public.payroll_runs;
create policy runs_read on public.payroll_runs for select to authenticated using(payroll_private.role(company_id) in ('admin','accountant') or (payroll_private.role(company_id)='staff' and payroll_private.staff_run_access(id)));
drop policy lines_read on public.payroll_lines;
create policy lines_read on public.payroll_lines for select to authenticated using(payroll_private.role(company_id) in ('admin','accountant') or (payroll_private.role(company_id)='staff' and payroll_private.own(staff_id) and payroll_private.staff_run_access(run_id)));
drop policy deposits_read on public.payroll_deposits;
create policy deposits_read on public.payroll_deposits for select to authenticated using(payroll_private.role(company_id) in ('admin','accountant'));
drop policy staff_details_read on public.payroll_staff_details;
create policy staff_details_read on public.payroll_staff_details for select to authenticated using(payroll_private.role(company_id) in ('admin','hr'));
drop policy late_reviews_read on public.payroll_late_reviews;
create policy late_reviews_read on public.payroll_late_reviews for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or (payroll_private.role(company_id)<>'staff' and payroll_private.late_can_review(staff_id)));

create or replace function payroll_private.dispatch(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by)
   values(cid,sid,(payload->>'joining_date')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,uid);
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
  insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,uid);
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
  select count(*) into units from generate_series((payload->>'from_date')::date,(payload->>'to_date')::date,interval '1 day')d where c.settings->'working_days' @> jsonb_build_array(extract(isodow from d)::int) and not c.settings->'holidays' @> jsonb_build_array(d::date::text);
  if (payload->>'half_day')::boolean then units=units/2;end if;
  if units<=0 then raise exception 'No working leave days in this request';end if;
  select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=payload->>'leave_type';
  if not found then raise exception 'Leave type not found';end if;
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
  units=(payload->>'units')::numeric;balance=coalesce((st.leave_balances->>(payload->>'leave_type'))::numeric,0)+units;
  if balance<0 or length(coalesce(payload->>'reason',''))<3 then raise exception 'Invalid balance or reason';end if;
  update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[payload->>'leave_type'],to_jsonb(balance)) where id=sid;
  insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,payload->>'leave_type',units,payload->>'reason','adjustment');
 elsif action='leave_policy' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid,description) values(cid,upper(payload->>'code'),(payload->>'annual_entitlement')::numeric,(payload->>'paid')::boolean,payload->>'description') on conflict(company_id,code) do update set annual_entitlement=excluded.annual_entitlement,description=excluded.description;
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
  insert into public.payroll_increments(company_id,staff_id,effective_from,basic,da,hra,other,reason,created_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,payload->>'reason',uid) returning id into rec;
 elsif action='increment_decide' then
  select * into inc from public.payroll_increments where id=rec and company_id=cid for update;if not found then raise exception 'Increment not found';end if;
  if payload->>'decision'='accountant_reviewed' and inc.status='recommended' and r in ('admin','accountant') and inc.created_by<>uid then update public.payroll_increments set status='accountant_reviewed',reviewed_by=uid where id=rec;
  elsif payload->>'decision'='approved' and inc.status='accountant_reviewed' and r='admin' then
   if exists(select 1 from public.payroll_runs where company_id=cid and month>=date_trunc('month',inc.effective_from)::date and status in ('locked','released','paid')) then raise exception 'Payroll was locked after recommendation; use reviewed arrears';end if;
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by) values(cid,inc.staff_id,inc.effective_from,inc.basic,inc.da,inc.hra,inc.other,uid);
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
end$$;
notify pgrst,'reload schema';
