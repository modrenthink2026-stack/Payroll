-- Deny stale tokens for banned, deleted or missing Payroll accounts.
do $$begin if md5(pg_get_functiondef('payroll_private.role(uuid)'::regprocedure)) <> 'b08307892746ac923d071726b1de62f7' then raise exception 'Security helper changed; re-review before applying this upgrade'; end if;end$$;
do $$begin if md5(pg_get_functiondef('payroll_private.platform_admin()'::regprocedure)) <> '03f7a7e6580cd19b025afc5f01ae9e6c' then raise exception 'Security helper changed; re-review before applying this upgrade'; end if;end$$;
-- PATCH
CREATE OR REPLACE FUNCTION payroll_private.role(cid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when m.role in ('admin','principal','president') or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office in ('principal','president')) then 'admin'
 when m.role='hr' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='hr') then 'hr' when m.role='director' or exists(select 1 from public.payroll_leave_approvers a where a.company_id=cid and a.user_id=auth.uid() and a.office='director') then 'manager' else m.role end
 from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid()
 and exists(select 1 from auth.users u where u.id=auth.uid() and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
 and not exists(select 1 from auth.users u where u.id=auth.uid() and coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false))
 and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='separated')
 and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='active'))
$function$
;
CREATE OR REPLACE FUNCTION payroll_private.platform_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.payroll_platform_admins where user_id=auth.uid()) and exists(select 1 from auth.users u where u.id=auth.uid() and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()) and not coalesce((u.raw_app_meta_data->>'payroll_password_change_required')::boolean,false))
$function$
;

