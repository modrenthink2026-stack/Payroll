-- Department attendance loading and atomic editing, reusing the reviewed attendance write path.
create function payroll_private.bulk_attendance(payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid(); workday date=(payload->>'work_date')::date; reqtoken uuid=(payload->>'request_id')::uuid;
 ids uuid[]; j jsonb; st public.payroll_staff; att public.payroll_attendance; source text; result jsonb; count_rows int=0;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and not coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Confirmed login and personal password required';end if;
 if coalesce(payroll_private.role(cid),'') not in ('admin','hr') then raise exception 'HR access required for attendance editing';end if;
 if workday is null or payload->>'department' is null then raise exception 'Choose a department and attendance date';end if;
 if payload->>'mode'='load' then
  select coalesce(jsonb_agg(jsonb_build_object('staff_id',s.id,'staff',jsonb_build_object('name',s.name,'code',s.code,'employee_ref',s.employee_ref,'shift_name',s.shift_name,'shift_start',s.shift_start,'shift_end',s.shift_end),'attendance',to_jsonb(a),'source_hash',md5((to_jsonb(s)-'leave_balances')::text||(case when a.id is null then 'null' else to_jsonb(a)::text end))) order by s.name,s.id),'[]'::jsonb) into result
  from public.payroll_staff s left join public.payroll_attendance a on a.staff_id=s.id and a.work_date=workday
  where s.company_id=cid and s.department=payload->>'department' and s.status='active' and s.joining_date<=workday and (s.leaving_date is null or s.leaving_date>=workday);
  return result;
 end if;
 if payload->>'mode' is distinct from 'save' then raise exception 'Invalid bulk attendance action';end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if reqtoken is null then raise exception 'Request ID required';end if;
 select response into result from payroll_private.requests where token=reqtoken and company_id=cid and user_id=uid and operation='bulk_attendance' and request_hash=md5(payload::text);
 if found then return result;end if;
 if exists(select 1 from payroll_private.requests where token=reqtoken) then raise exception 'Request ID reused with different data';end if;
 if length(trim(coalesce(payload->>'reason',''))) not between 3 and 500 then raise exception 'Enter a review reason (3–500 characters)';end if;
 if jsonb_typeof(payload->'rows') is distinct from 'array' then raise exception 'Select attendance rows';end if;
 if jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Select 1 to 500 staff';end if;
 select array_agg((v->>'staff_id')::uuid) into ids from jsonb_array_elements(payload->'rows') v;
 if (select count(distinct x) from unnest(ids) x)<>cardinality(ids) then raise exception 'Duplicate or missing staff selection';end if;
 perform 1 from public.payroll_staff where company_id=cid and id=any(ids) order by id for update;
 if (select count(*) from public.payroll_staff where company_id=cid and id=any(ids) and status='active' and department=payload->>'department' and joining_date<=workday and (leaving_date is null or leaving_date>=workday))<>cardinality(ids) then raise exception 'Staff or department changed; reload attendance';end if;
 for j in select * from jsonb_array_elements(payload->'rows') loop
  select * into st from public.payroll_staff where id=(j->>'staff_id')::uuid and company_id=cid;
  select * into att from public.payroll_attendance where staff_id=st.id and work_date=workday for update;
  source=md5((to_jsonb(st)-'leave_balances')::text||(case when att.id is null then 'null' else to_jsonb(att)::text end));
  if j->>'source_hash' is distinct from source then raise exception 'Attendance or staff shift changed; reload before saving';end if;
  if coalesce(j->>'status','') not in ('present','absent','half_day','holiday') then raise exception 'Choose a valid attendance status';end if;
  if coalesce(j->>'late_minutes','') !~ '^[0-9]+$' or coalesce(j->>'early_minutes','') !~ '^[0-9]+$' or (j->>'late_minutes')::numeric>1440 or (j->>'early_minutes')::numeric>1440 then raise exception 'Late and early minutes must be whole minutes from 0 to 1440';end if;
  if length(coalesce(j->>'note',''))>500 then raise exception 'Row note must be at most 500 characters';end if;
  perform payroll_private.dispatch('attendance_save',jsonb_build_object('company_id',cid,'staff_id',st.id,'from_date',workday,'to_date',workday,'status',j->>'status','in_time',j->>'in_time','out_time',j->>'out_time','late_minutes',j->>'late_minutes','early_minutes',j->>'early_minutes','calculate_shift',coalesce((j->>'calculate_shift')::boolean,false),'out_next_day',coalesce((j->>'out_next_day')::boolean,false),'note',trim(payload->>'reason')||case when nullif(j->>'note','') is null then '' else ' · '||(j->>'note') end));
  count_rows=count_rows+1;
 end loop;
 result=jsonb_build_object('updated',count_rows);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqtoken,cid,uid,'bulk_attendance',md5(payload::text),result);
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'bulk_attendance',reqtoken::text);
 return result;
end$$;
revoke all on function payroll_private.bulk_attendance(jsonb) from public,anon;
grant execute on function payroll_private.bulk_attendance(jsonb) to authenticated;
create function public.payroll_bulk_attendance(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.bulk_attendance(payload)$$;
revoke all on function public.payroll_bulk_attendance(jsonb) from public,anon;
grant execute on function public.payroll_bulk_attendance(jsonb) to authenticated;
notify pgrst,'reload schema';
