-- One transaction for a month's reviewed report, reusing all existing attendance guards.
create or replace function payroll_private.monthly_attendance(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid(); m date=(payload->>'month')::date;
 reqtoken uuid=(payload->>'request_id')::uuid; result jsonb; group_row record; n int; updated_count int=0;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and not coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Confirmed login and personal password required';end if;
 if coalesce(payroll_private.role(cid),'') not in ('admin','hr') then raise exception 'HR access required for attendance editing';end if;
 perform payroll_private.platform_direct_guard(payload,'attendance');
 if m is null or m<>date_trunc('month',m)::date then raise exception 'Choose the first day of a report month';end if;
 if coalesce(payload->>'mode','') not in ('load','save') then raise exception 'Invalid monthly attendance action';end if;
 if payload->>'mode'='save' then
  if reqtoken is null then raise exception 'Request ID required';end if;
  select response into result from payroll_private.requests where requests.token=reqtoken and company_id=cid and user_id=uid and operation='monthly_attendance' and request_hash=md5(payload::text);
  if found then return result;end if;
  if exists(select 1 from payroll_private.requests where requests.token=reqtoken) then raise exception 'Request ID reused with different data';end if;
  if length(trim(coalesce(payload->>'reason',''))) not between 3 and 500 then raise exception 'Enter a review reason (3-500 characters)';end if;
 end if;
 if jsonb_typeof(payload->'rows') is distinct from 'array' then raise exception 'Upload attendance rows';end if;
 n=jsonb_array_length(payload->'rows');
 if n not between 1 and 15500 then raise exception 'Upload 1 to 15,500 attendance rows';end if;
 if exists(select 1 from jsonb_array_elements(payload->'rows') j where nullif(j->>'staff_id','') is null or coalesce(j->>'work_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or (j->>'work_date')::date<m or (j->>'work_date')::date>=(m+interval '1 month')::date) then raise exception 'Every row must have a staff ID and a date in the selected month';end if;
 if exists(select 1 from jsonb_array_elements(payload->'rows') j group by (j->>'staff_id')::uuid,(j->>'work_date')::date having count(*)>1) then raise exception 'Duplicate employee/date';end if;
 if (select count(*) from jsonb_array_elements(payload->'rows') j join public.payroll_staff s on s.id=(j->>'staff_id')::uuid and s.company_id=cid and s.status='active' and s.joining_date<=(j->>'work_date')::date and (s.leaving_date is null or s.leaving_date>=(j->>'work_date')::date))<>n then raise exception 'Unknown, inactive or out-of-employment staff';end if;
 if payload->>'mode'='load' then
  select jsonb_agg(jsonb_build_object('staff_id',s.id,'work_date',(j->>'work_date')::date,
   'staff',jsonb_build_object('id',s.id,'name',s.name,'code',s.code,'employee_ref',s.employee_ref,'department',s.department,'biometric_id',s.biometric_id,'status',s.status,'joining_date',s.joining_date,'leaving_date',s.leaving_date,'shift_name',s.shift_name,'shift_start',s.shift_start,'shift_end',s.shift_end,'early_grace',s.early_grace),
   'attendance',to_jsonb(a),'source_hash',md5((to_jsonb(s)-'leave_balances')::text||case when a.id is null then 'null' else to_jsonb(a)::text end)) order by j->>'work_date',s.department,s.name,s.id) into result
  from jsonb_array_elements(payload->'rows') j join public.payroll_staff s on s.id=(j->>'staff_id')::uuid and s.company_id=cid
  left join public.payroll_attendance a on a.staff_id=s.id and a.company_id=cid and a.work_date=(j->>'work_date')::date;
  return result;
 end if;
 -- The company/module lock from platform_direct_guard serializes other attendance saves.
 for group_row in
  select s.department,(j->>'work_date')::date work_date,jsonb_agg(j order by s.id) rows
  from jsonb_array_elements(payload->'rows') j join public.payroll_staff s on s.id=(j->>'staff_id')::uuid and s.company_id=cid
  group by s.department,(j->>'work_date')::date order by (j->>'work_date')::date,s.department
 loop
  result=payroll_private.bulk_attendance(jsonb_build_object('mode','save','company_id',cid,'department',group_row.department,'work_date',group_row.work_date,'reason',payload->>'reason','rows',group_row.rows,'request_id',gen_random_uuid()));
  updated_count=updated_count+(result->>'updated')::int;
 end loop;
 result=jsonb_build_object('updated',updated_count);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqtoken,cid,uid,'monthly_attendance',md5(payload::text),result);
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'monthly_attendance',reqtoken::text);
 return result;
end$$;
revoke all on function payroll_private.monthly_attendance(jsonb) from public,anon;
grant execute on function payroll_private.monthly_attendance(jsonb) to authenticated;
create or replace function public.payroll_monthly_attendance(payload jsonb) returns jsonb
language sql security invoker set search_path='' as $$select payroll_private.monthly_attendance(payload)$$;
revoke all on function public.payroll_monthly_attendance(jsonb) from public,anon;
grant execute on function public.payroll_monthly_attendance(jsonb) to authenticated;
notify pgrst,'reload schema';
