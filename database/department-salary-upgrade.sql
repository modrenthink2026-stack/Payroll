-- Atomic department salary entry using the existing initial/increment authorization paths.
create function payroll_private.department_salaries(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid(); reqtoken uuid=(payload->>'request_id')::uuid;
 ids uuid[]; j jsonb; latest public.payroll_salaries; effective date=(payload->>'effective_from')::date;
 initial_count int=0; recommendation_count int=0; result jsonb; amount_key text;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed login required';end if;
 if payroll_private.role(cid) is distinct from 'admin' then raise exception 'Full company access required for salary entry';end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if reqtoken is null then raise exception 'Request ID required';end if;
 select response into result from payroll_private.requests where requests.token=reqtoken and company_id=cid and user_id=uid and operation='department_salaries' and request_hash=md5(payload::text);
 if found then return result;end if;
 if exists(select 1 from payroll_private.requests where requests.token=reqtoken) then raise exception 'Request ID reused with different data';end if;
 if payload->>'department' is null or effective is null or length(trim(coalesce(payload->>'reason','')))<3 then raise exception 'Choose a department, effective date and reason';end if;
 if jsonb_typeof(payload->'rows') is distinct from 'array' then raise exception 'Select staff salary rows';end if;
 if jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Select 1 to 500 staff';end if;
 select array_agg((v->>'staff_id')::uuid) into ids from jsonb_array_elements(payload->'rows') v;
 if (select count(distinct x) from unnest(ids) x)<>cardinality(ids) then raise exception 'Duplicate or missing staff selection';end if;
 perform 1 from public.payroll_staff where company_id=cid and id=any(ids) order by id for update;
 if (select count(*) from public.payroll_staff where company_id=cid and id=any(ids) and status='active' and department=payload->>'department')<>cardinality(ids) then raise exception 'Staff or department changed; reload the salary editor';end if;
 for j in select * from jsonb_array_elements(payload->'rows') loop
  if j->>'salary_mode'='consolidated' then j=j||jsonb_build_object('basic',0,'da',0,'hra',0,'cca',0,'hod_allowance',0,'other',coalesce(j->>'consolidated_amount',j->>'other','0'));end if;
  foreach amount_key in array array['basic','da','hra','cca','other','hod_allowance'] loop
   if coalesce(j->>amount_key,'') !~ '^[0-9]+(\.[0-9]{1,2})?$' then raise exception 'Enter non-negative amounts with at most two decimals';end if;
  end loop;
  select * into latest from public.payroll_salaries where staff_id=(j->>'staff_id')::uuid order by effective_from desc,id desc limit 1;
  if latest.id is distinct from nullif(j->>'expected_salary_id','')::uuid then raise exception 'Salary changed; reload before saving';end if;
  if latest.id is not null then
   if effective<=latest.effective_from then raise exception 'Revision date must follow the latest salary version';end if;
   if exists(select 1 from public.payroll_increments where staff_id=latest.staff_id and effective_from=effective and status in ('recommended','accountant_reviewed')) then raise exception 'A salary recommendation already awaits review for this date';end if;
   perform payroll_private.dispatch('increment_save',(j-'request_id')||jsonb_build_object('company_id',cid,'effective_from',effective,'reason',trim(payload->>'reason'),'request_id',null));
   recommendation_count=recommendation_count+1;
  else
   perform payroll_private.dispatch('initial_salary',(j-'request_id')||jsonb_build_object('company_id',cid,'effective_from',effective,'request_id',null));
   initial_count=initial_count+1;
  end if;
 end loop;
 result=jsonb_build_object('initial',initial_count,'recommended',recommendation_count);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqtoken,cid,uid,'department_salaries',md5(payload::text),result);
 return result;
end$$;
revoke all on function payroll_private.department_salaries(jsonb) from public,anon;
grant execute on function payroll_private.department_salaries(jsonb) to authenticated;
create function public.payroll_department_salaries(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.department_salaries(payload)$$;
revoke all on function public.payroll_department_salaries(jsonb) from public,anon;
grant execute on function public.payroll_department_salaries(jsonb) to authenticated;
notify pgrst,'reload schema';
