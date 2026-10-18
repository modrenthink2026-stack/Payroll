alter table public.payroll_members drop constraint payroll_members_role_check;
alter table public.payroll_members add constraint payroll_members_role_check check(role in ('admin','principal','president','director','hr','accountant','manager','staff'));
create or replace function payroll_private.role(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select case when m.role in ('admin','principal','president') or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office in ('principal','president')) then 'admin'
 when m.role='hr' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='hr') then 'hr' when m.role='director' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='director') then 'manager' else m.role end
 from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid()
 and not exists(select 1 from auth.users u where u.id=auth.uid() and coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false))
 and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='separated')
 and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='active'))
$$;
create or replace function payroll_private.display_role(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select case when m.role in ('admin','principal','president','director') then m.role
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='principal') then 'principal'
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='president') then 'president'
 when exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='director') then 'director' else payroll_private.role(cid) end from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid() and payroll_private.role(cid) is not null
$$;
