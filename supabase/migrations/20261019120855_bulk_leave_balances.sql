-- Atomic opening/current leave balance entry, with deltas retained in the existing ledger.
create function payroll_private.bulk_leave_balances(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid(); reqtoken uuid=(payload->>'request_id')::uuid;
 ids uuid[]; j jsonb; pair record; st public.payroll_staff; old_balance numeric; target_balance numeric; reserved numeric; changed int=0; result jsonb;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and not coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Confirmed login and personal password required';end if;
 if coalesce(payroll_private.role(cid),'') not in ('admin','hr') then raise exception 'HR access required for leave balances';end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if reqtoken is null then raise exception 'Request ID required';end if;
 select response into result from payroll_private.requests where token=reqtoken and company_id=cid and user_id=uid and operation='bulk_leave_balances' and request_hash=md5(payload::text);
 if found then return result;end if;
 if exists(select 1 from payroll_private.requests where token=reqtoken) then raise exception 'Request ID reused with different data';end if;
 if length(trim(coalesce(payload->>'reason',''))) not between 3 and 500 then raise exception 'Enter an opening balance period or adjustment reason (3–500 characters)';end if;
 if jsonb_typeof(payload->'rows') is distinct from 'array' then raise exception 'Select staff balance rows';end if;
 if jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Select 1 to 500 staff';end if;
 select array_agg((v->>'staff_id')::uuid) into ids from jsonb_array_elements(payload->'rows') v;
 if (select count(distinct x) from unnest(ids) x)<>cardinality(ids) then raise exception 'Duplicate or missing staff selection';end if;
 perform 1 from public.payroll_staff where company_id=cid and id=any(ids) order by id for update;
 if (select count(*) from public.payroll_staff where company_id=cid and id=any(ids) and status='active' and (payload->>'department' is null or department=payload->>'department'))<>cardinality(ids) then raise exception 'Staff or department changed; reload the balance editor';end if;
 for j in select * from jsonb_array_elements(payload->'rows') loop
  select * into st from public.payroll_staff where id=(j->>'staff_id')::uuid and company_id=cid;
  if jsonb_typeof(j->'balances') is distinct from 'object' or jsonb_typeof(j->'expected_balances') is distinct from 'object' then raise exception 'Enter balances and their current values';end if;
  if (select count(*) from jsonb_object_keys(j->'balances')) not between 1 and 50 then raise exception 'Enter 1 to 50 leave types per staff member';end if;
  for pair in select key,value from jsonb_each_text(j->'balances') loop
   if not exists(select 1 from public.payroll_leave_policies where company_id=cid and code=pair.key and paid) then raise exception 'Choose a paid leave type from this company';end if;
   if coalesce(pair.value,'') !~ '^[0-9]+(\.[0-9]+)?$' or pair.value::numeric>9999.5 or mod(pair.value::numeric,0.5)<>0 then raise exception 'Balances must be 0–9999.5 days in half-day steps';end if;
   old_balance=coalesce((st.leave_balances->>pair.key)::numeric,0);target_balance=pair.value::numeric;
   if coalesce(j->'expected_balances'->>pair.key,'') !~ '^[0-9]+(\.[0-9]+)?$' or (j->'expected_balances'->>pair.key)::numeric<>old_balance then raise exception 'Leave balance changed; reload before saving';end if;
   select coalesce(sum(units),0) into reserved from public.payroll_leaves where company_id=cid and staff_id=st.id and leave_type=pair.key and status='submitted';
   if target_balance<reserved then raise exception 'Balance cannot be less than pending leave reservations';end if;
   if target_balance<>old_balance then
    update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[pair.key],to_jsonb(target_balance)) where id=st.id;
    insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,st.id,pair.key,target_balance-old_balance,trim(payload->>'reason'),'bulk_balance');
    changed=changed+1;
   end if;
  end loop;
 end loop;
 result=jsonb_build_object('staff',cardinality(ids),'changed_balances',changed);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqtoken,cid,uid,'bulk_leave_balances',md5(payload::text),result);
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'bulk_leave_balances',reqtoken::text);
 return result;
end$$;
revoke all on function payroll_private.bulk_leave_balances(jsonb) from public,anon;
grant execute on function payroll_private.bulk_leave_balances(jsonb) to authenticated;
create function public.payroll_bulk_leave_balances(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.bulk_leave_balances(payload)$$;
revoke all on function public.payroll_bulk_leave_balances(jsonb) from public,anon;
grant execute on function public.payroll_bulk_leave_balances(jsonb) to authenticated;
notify pgrst,'reload schema';
