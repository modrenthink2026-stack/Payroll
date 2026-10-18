-- Isolated department / selected-staff shift assignment; no dispatcher replacement.
create function payroll_private.assign_shifts(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); cid uuid=(payload->>'company_id')::uuid; r text; selected_ids uuid[];
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed login required';end if;
 r=payroll_private.role(cid);
 if r is null then raise exception 'No access to this company';end if;
 perform 1 from public.payroll_companies where id=cid for update;
  if r not in ('admin','hr') then raise exception 'HR or full company access required';end if;
  if jsonb_typeof(payload->'staff_ids') is distinct from 'array' then raise exception 'Select staff';end if;
  if jsonb_array_length(payload->'staff_ids') not between 1 and 500 then raise exception 'Select 1 to 500 staff';end if;
  select array_agg(value::uuid) into selected_ids from jsonb_array_elements_text(payload->'staff_ids');
  if (select count(distinct x) from unnest(selected_ids) x)<>cardinality(selected_ids) then raise exception 'Duplicate staff selection';end if;
  if nullif(trim(payload->>'shift_name'),'') is null or nullif(payload->>'shift_start','') is null or nullif(payload->>'shift_end','') is null then raise exception 'Enter shift name and timings';end if;
  perform 1 from public.payroll_staff where company_id=cid and id=any(selected_ids) order by id for update;
  if (select count(*) from public.payroll_staff where company_id=cid and id=any(selected_ids) and status='active' and (payload->>'department' is null or department=payload->>'department'))<>cardinality(selected_ids) then raise exception 'Staff selection changed or includes unavailable staff; reload and select again';end if;
  update public.payroll_staff set shift_name=trim(payload->>'shift_name'),shift_start=(payload->>'shift_start')::time,shift_end=(payload->>'shift_end')::time,
   break_minutes=coalesce((payload->>'break_minutes')::int,0),late_grace=coalesce((payload->>'late_grace')::int,0),early_grace=coalesce((payload->>'early_grace')::int,0)
   where company_id=cid and id=any(selected_ids);
 insert into public.payroll_audit(company_id,actor,action) values(cid,uid,'shift_assign');
 return jsonb_build_object('ok',true,'updated',cardinality(selected_ids));
end$$;
revoke all on function payroll_private.assign_shifts(jsonb) from public,anon;
grant execute on function payroll_private.assign_shifts(jsonb) to authenticated;
create function public.payroll_assign_shifts(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.assign_shifts(payload)$$;
revoke all on function public.payroll_assign_shifts(jsonb) from public,anon;
grant execute on function public.payroll_assign_shifts(jsonb) to authenticated;
notify pgrst,'reload schema';
