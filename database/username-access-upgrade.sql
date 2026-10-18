-- Resolve a company-local username before using the existing role-assignment rules.
create function payroll_private.username_role(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid(); account_email text;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed login required';end if;
 if payroll_private.role(cid) is distinct from 'admin' then raise exception 'Full company access required';end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if nullif(trim(payload->>'username'),'') is null or position('@' in payload->>'username')>0 then raise exception 'Select a staff username, not an email address';end if;
 select u.email into account_email from public.payroll_staff s join auth.users u on u.id=s.user_id
 where s.company_id=cid and s.status='active' and lower(s.login_name)=lower(trim(payload->>'username')) and u.email_confirmed_at is not null;
 if account_email is null then raise exception 'Active username not found in this company; activate the staff login first';end if;
 return payroll_private.dispatch('member_grant',jsonb_build_object('company_id',cid,'email',account_email,'role',payload->>'role','request_id',payload->>'request_id'));
end$$;
revoke all on function payroll_private.username_role(jsonb) from public,anon;
grant execute on function payroll_private.username_role(jsonb) to authenticated;
create function public.payroll_username_role(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.username_role(payload)$$;
revoke all on function public.payroll_username_role(jsonb) from public,anon;
grant execute on function public.payroll_username_role(jsonb) to authenticated;
notify pgrst,'reload schema';
