-- Exact seconds for new raw-register saves; legacy reviewed minutes retain their meaning.
CREATE OR REPLACE FUNCTION payroll_private.late_plan(sid uuid, m date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.payroll_staff;c public.payroll_companies;a record;remaining int=1500;used int=0;total int=0;uncovered int=0;events jsonb='[]';h text;
begin
 if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a payroll month';end if;
 select * into s from public.payroll_staff where id=sid;if not found then raise exception 'Staff not found';end if;
 select * into c from public.payroll_companies where id=s.company_id;
 for a in select at.id,at.work_date,to_char(at.in_time,'HH24:MI:SS') as in_time,coalesce(at.shift_snapshot->>'start',to_char(s.shift_start,'HH24:MI:SS')) as reporting_time,coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60) as mins from public.payroll_attendance at
 where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date
 and at.work_date>=s.joining_date and at.work_date<=coalesce(s.leaving_date,'infinity'::date) and at.status='present'
 and coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60)>0
 and c.settings->'working_days' @> jsonb_build_array(extract(isodow from at.work_date)::int)
 and not c.settings->'holidays' @> jsonb_build_array(at.work_date::text)
 and not exists(select 1 from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and at.work_date between l.from_date and l.to_date)
 order by coalesce((at.shift_snapshot->>'raw_late_seconds')::int,coalesce(at.raw_late_minutes,at.late_minutes)*60),at.work_date,at.id loop
  total=total+a.mins;
  if a.mins<=remaining then remaining=remaining-a.mins;used=used+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'seconds',a.mins,'cumulative_seconds',total,'minutes',a.mins::numeric/60,'cumulative_minutes',total::numeric/60,'covered',true));
  else uncovered=uncovered+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'seconds',a.mins,'cumulative_seconds',total,'minutes',a.mins::numeric/60,'cumulative_minutes',total::numeric/60,'covered',false));
  end if;
 end loop;
 h=md5(jsonb_build_array(m,25,s.id,s.joining_date,s.leaving_date,c.settings->'working_days',c.settings->'holidays',
 (select jsonb_agg(to_jsonb(at) order by at.work_date,at.id) from public.payroll_attendance at where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date),
 (select jsonb_agg(jsonb_build_array(l.id,l.from_date,l.to_date,l.half_day,l.leave_type) order by l.id) from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and l.to_date>=m and l.from_date<(m+interval '1 month')::date))::text);
 return jsonb_build_object('month',m,'allowance',25,'allowance_seconds',1500,'total_seconds',total,'used_seconds',used,'unused_seconds',remaining,'uncovered_seconds',uncovered,'total_minutes',total::numeric/60,'used_minutes',used::numeric/60,'unused_minutes',remaining::numeric/60,'net_excess_minutes',greatest(0,total-1500)::numeric/60,'uncovered_minutes',uncovered::numeric/60,'events',events,'source_hash',h);
end$function$;

-- Reuse the existing company-scoped register, locks, module switches, evidence hashes
-- and HR confirmation. No direct table grants and no automatic leave/payroll deductions.
create function payroll_private.raw_biometric(payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid=(payload->>'company_id')::uuid;m date=(payload->>'month')::date;
 op text=payload->>'mode';result jsonb;j jsonb;prepared jsonb='[]';saved jsonb;period_hash text;st public.payroll_staff;
 ins jsonb;outs jsonb;start_time time;end_time time;arr time;dep time;sec int;early int;req uuid;old_response jsonb;
begin
 -- The existing register performs confirmed-login, tenant, role and module checks.
 result=payroll_private.attendance_register(jsonb_build_object('company_id',cid,'month',m,'mode','load'));
 if coalesce(op,'') not in ('load','import','save_normal') then raise exception 'Invalid raw biometric action';end if;
 if op<>'load' then
  if coalesce(payroll_private.role(cid),'') not in ('admin','hr') then raise exception 'HR access required';end if;
  req=(payload->>'request_id')::uuid;if req is null then raise exception 'Request ID required';end if;
  select response into old_response from payroll_private.requests where token=req and company_id=cid and user_id=auth.uid() and operation='raw_biometric' and request_hash=md5(payload::text);
  if found then return old_response;end if;
  if exists(select 1 from payroll_private.requests where token=req) then raise exception 'Request ID reused with different data';end if;
  if payload->>'source_hash' is distinct from result->>'source_hash' then raise exception 'Attendance inputs changed; reload before continuing';end if;
 end if;
 if op='import' then
  -- Raw files never claim manual entry or accept arbitrary staff/company mappings.
  if exists(select 1 from jsonb_array_elements(payload->'rows') x where x->'manual_entry' is distinct from 'false'::jsonb) then raise exception 'Raw uploads must be biometric punches, not manual corrections';end if;
  result=payroll_private.attendance_register(jsonb_build_object('mode','import','company_id',cid,'month',m,'rows',payload->'rows','reason',payload->>'reason','request_id',gen_random_uuid()));
 elsif op='save_normal' then
  -- Prepare ordinary complete day shifts server-side. Existing attendance is never overwritten.
  for j in select * from jsonb_array_elements(result->'rows') loop
   if not (j->>'working_day')::boolean or coalesce((j->>'leave_count')::int,0)>0 or j->'attendance'<>'null'::jsonb then continue;end if;
   select coalesce(jsonb_agg(x),'[]') into ins from jsonb_array_elements(j->'punches') x where x->>'direction'='in';
   select coalesce(jsonb_agg(x),'[]') into outs from jsonb_array_elements(j->'punches') x where x->>'direction'='out';
   if jsonb_array_length(ins)<>1 or jsonb_array_length(outs)<>1 or exists(select 1 from jsonb_array_elements(j->'punches') x where coalesce((x->>'manual_entry')::boolean,false)) then continue;end if;
   select * into st from public.payroll_staff where company_id=cid and id=(j->>'staff_id')::uuid;
   start_time=st.shift_start;end_time=st.shift_end;arr=(ins->0->>'time')::time;dep=(outs->0->>'time')::time;
   if start_time is null or end_time is null or end_time<=start_time or dep<=arr or (start_time<'12:00' and arr>='12:00') or (end_time>='12:00' and dep<'12:00') then continue;end if;
   sec=greatest(0,extract(epoch from (arr-start_time))::int);early=greatest(0,floor(extract(epoch from(end_time-dep))/60)::int-coalesce(st.early_grace,0));
   prepared=prepared||jsonb_build_array(jsonb_build_object('staff_id',st.id,'work_date',j->>'work_date','status','present','in_time',arr,'out_time',dep,'late_minutes',sec/60,'early_minutes',early,'out_next_day',false,'note','Raw biometric: exact seconds retained; complete IN/OUT reviewed in bulk','raw_late_seconds',sec));
  end loop;
  if jsonb_array_length(prepared)=0 then raise exception 'No new complete day-shift rows are available; review exceptions or existing attendance';end if;
  saved=payroll_private.attendance_register(jsonb_build_object('mode','save','company_id',cid,'month',m,'source_hash',result->>'source_hash','rows',prepared,'reason',payload->>'reason','request_id',gen_random_uuid()));
  for j in select * from jsonb_array_elements(prepared) loop
   select * into st from public.payroll_staff where company_id=cid and id=(j->>'staff_id')::uuid;
   update public.payroll_attendance set shift_snapshot=jsonb_build_object('name',st.shift_name,'start',st.shift_start,'end',st.shift_end,'early_grace',st.early_grace,'out_next_day',false,'raw_late_seconds',(j->>'raw_late_seconds')::int,'source','raw_biometric_v1')
   where company_id=cid and staff_id=st.id and work_date=(j->>'work_date')::date;
  end loop;
  result=payroll_private.attendance_register(jsonb_build_object('company_id',cid,'month',m,'mode','load'))||jsonb_build_object('updated',jsonb_array_length(prepared));
 end if;
 result=result||jsonb_build_object('company_id',cid,'month',m,'late_plans',coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'plan',payroll_private.late_plan(s.id,m),'review',(select to_jsonb(lr) from public.payroll_late_reviews lr where lr.company_id=cid and lr.staff_id=s.id and lr.month=m and lr.status='active'))) from public.payroll_staff s where s.company_id=cid and s.joining_date<(m+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>=m),'[]'::jsonb));
 if op<>'load' then
  insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(req,cid,auth.uid(),'raw_biometric',md5(payload::text),result);
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,auth.uid(),'raw_biometric_'||op,m::text);
 end if;
 return result;
end$$;
revoke all on function payroll_private.raw_biometric(jsonb) from public,anon;
grant execute on function payroll_private.raw_biometric(jsonb) to authenticated;
create function public.payroll_raw_biometric(payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select payroll_private.raw_biometric(payload)$$;
revoke all on function public.payroll_raw_biometric(jsonb) from public,anon;
grant execute on function public.payroll_raw_biometric(jsonb) to authenticated;
notify pgrst,'reload schema';
