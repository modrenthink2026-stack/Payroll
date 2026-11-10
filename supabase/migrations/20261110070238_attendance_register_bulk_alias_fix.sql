-- Replace the per-punch import loop with atomic batch validation and insertion.
CREATE OR REPLACE FUNCTION payroll_private.attendance_register(payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid=(payload->>'company_id')::uuid; uid uuid=auth.uid();m date=(payload->>'month')::date;
 op text=payload->>'mode';reqtoken uuid;result jsonb;rows jsonb;hash text;issues int;pending int;late_pending int;
 j jsonb;s public.payroll_staff;d date;t time;manual boolean;n int=0;r text;reason text=trim(payload->>'reason');period payroll_private.attendance_periods;
begin
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and not coalesce((raw_app_meta_data->>'payroll_password_change_required')::boolean,false)) then raise exception 'Confirmed login and personal password required';end if;
 r=payroll_private.role(cid);if coalesce(r,'') not in ('admin','hr','accountant') then raise exception 'Attendance register access required';end if;
 perform 1 from public.payroll_companies where id=cid for update;
 if m is null or m<>date_trunc('month',m)::date or m<'2000-01-01' or m>'2099-12-01' then raise exception 'Choose the first day of a report month from 2000 to 2099';end if;
 if coalesce(op,'') not in ('load','import','save','finalize','reopen') then raise exception 'Invalid attendance register action';end if;
 select * into period from payroll_private.attendance_periods where company_id=cid and month=m;
 if op<>'load' then
  if r not in ('admin','hr') then raise exception 'HR access required for attendance editing';end if;
  if not payroll_private.module_enabled(cid,'attendance') or not payroll_private.module_enabled(cid,'attendance_register_v1') then raise exception 'Attendance register v1 is disabled for this company';end if;
  if length(coalesce(reason,'')) not between 3 and 500 then raise exception 'Enter a review reason (3-500 characters)';end if;
  reqtoken=(payload->>'request_id')::uuid;if reqtoken is null then raise exception 'Request ID required';end if;
  select response into result from payroll_private.requests where requests.token=reqtoken and company_id=cid and user_id=uid and operation='attendance_register_v1' and request_hash=md5(payload::text);
  if found then return result;end if;
  if exists(select 1 from payroll_private.requests where requests.token=reqtoken) then raise exception 'Request ID reused with different data';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month=m and status in ('locked','released','paid')) then raise exception 'Payroll month is locked; use a reviewed adjustment';end if;
  if period.status='finalized' and op<>'reopen' then raise exception 'Attendance is finalized; reopen the month before editing';end if;
 else
  if period.company_id is null and not payroll_private.module_enabled(cid,'attendance_register_v1') then raise exception 'Attendance register v1 is unavailable';end if;
 end if;
 hash=payroll_private.attendance_period_hash(cid,m);
 if op in ('save','finalize','reopen') and payload->>'source_hash' is distinct from hash then raise exception 'Attendance inputs changed; reload before continuing';end if;
 if op='import' then
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 62000 or octet_length(payload::text)>16000000 then raise exception 'Upload 1 to 62,000 punches';end if;
  -- Validate the entire batch before inserting; keep the existing company lock,
  -- access controls, month locks, retry handling and audit path above/below.
  if exists(select 1 from jsonb_array_elements(payload->'rows') punch_row where
   coalesce(punch_row->>'work_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(punch_row->>'log_time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$'
   or coalesce(punch_row->>'direction','') not in ('in','out')
   or jsonb_typeof(punch_row->'manual_entry') is distinct from 'boolean') then
   raise exception 'Invalid punch date, time, direction or manual-entry flag';
  end if;
  if exists(select 1 from jsonb_array_elements(payload->'rows') punch_row where
   (punch_row->>'work_date')::date<m or (punch_row->>'work_date')::date>=(m+interval '1 month')::date) then
   raise exception 'Every punch date must belong to the selected month';
  end if;
  if exists(select 1 from jsonb_array_elements(payload->'rows') punch_row left join public.payroll_staff st
   on st.company_id=cid and st.biometric_id=punch_row->>'biometric_id'
   where st.id is null
   or lower(trim(st.name)) is distinct from lower(trim(punch_row->>'name'))
   or (punch_row->>'work_date')::date<st.joining_date
   or (punch_row->>'work_date')::date>coalesce(st.leaving_date,'infinity'::date)
   or (st.status='separated' and st.leaving_date is null))
   or exists(select 1 from public.payroll_staff st where st.company_id=cid
    and st.biometric_id in(select punch_row->>'biometric_id' from jsonb_array_elements(payload->'rows') punch_row)
    group by st.biometric_id having count(*)>1) then
   raise exception 'Unknown employee, name mismatch or out-of-employment punch';
  end if;
  if exists(select 1 from jsonb_array_elements(payload->'rows') punch_row
   join public.payroll_staff st on st.company_id=cid and st.biometric_id=punch_row->>'biometric_id'
   join public.payroll_punches p on p.company_id=cid and p.staff_id=st.id
    and p.event_time=((punch_row->>'work_date')::date+(punch_row->>'log_time')::time) at time zone 'Asia/Kolkata'
    and p.direction=punch_row->>'direction' where p.manual_entry<>(punch_row->>'manual_entry')::boolean)
   or exists(select 1 from jsonb_array_elements(payload->'rows') punch_row
    group by punch_row->>'biometric_id',(punch_row->>'work_date')::date,(punch_row->>'log_time')::time,punch_row->>'direction'
    having count(distinct (punch_row->>'manual_entry')::boolean)>1) then
   raise exception 'Conflicting manual-entry flag for an existing punch';
  end if;
  insert into public.payroll_punches(company_id,staff_id,device_id,event_id,event_time,direction,manual_entry)
   select distinct cid,st.id,'full-log-v1',
    md5(st.id::text||(punch_row->>'work_date')::date::text||(punch_row->>'log_time')::time::text||(punch_row->>'direction')),
    ((punch_row->>'work_date')::date+(punch_row->>'log_time')::time) at time zone 'Asia/Kolkata',
    punch_row->>'direction',(punch_row->>'manual_entry')::boolean
   from jsonb_array_elements(payload->'rows') punch_row join public.payroll_staff st
    on st.company_id=cid and st.biometric_id=punch_row->>'biometric_id'
   where not exists(select 1 from public.payroll_punches p where p.company_id=cid and p.staff_id=st.id
    and p.event_time=((punch_row->>'work_date')::date+(punch_row->>'log_time')::time) at time zone 'Asia/Kolkata'
    and p.direction=punch_row->>'direction');
  get diagnostics n=row_count;
 elsif op='save' then
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 15500 then raise exception 'Select 1 to 15,500 reviewed attendance rows';end if;
  if exists(select 1 from jsonb_array_elements(payload->'rows') x group by x->>'staff_id',x->>'work_date' having count(*)>1) then raise exception 'Duplicate employee/date';end if;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   d=(j->>'work_date')::date;
   if d is null or d<m or d>=(m+interval '1 month')::date or coalesce(j->>'status','') not in ('present','absent','half_day','holiday') then raise exception 'Choose a reviewed status and date in this month';end if;
   if coalesce(j->>'late_minutes','') !~ '^[0-9]+$' or coalesce(j->>'early_minutes','') !~ '^[0-9]+$' or (j->>'late_minutes')::numeric>1440 or (j->>'early_minutes')::numeric>1440 or length(coalesce(j->>'note',''))>500 then raise exception 'Invalid reviewed minutes or note';end if;
   perform payroll_private.dispatch('attendance_save',j||jsonb_build_object('company_id',cid,'from_date',d,'to_date',d,'calculate_shift',false,'note',reason||case when nullif(j->>'note','') is null then '' else ' Â· '||(j->>'note') end));
   if coalesce((j->>'out_next_day')::boolean,false) then
    select * into s from public.payroll_staff where company_id=cid and id=(j->>'staff_id')::uuid;
    update public.payroll_attendance set shift_snapshot=jsonb_build_object('name',s.shift_name,'start',s.shift_start,'end',s.shift_end,'early_grace',s.early_grace,'out_next_day',true) where company_id=cid and staff_id=s.id and work_date=d;
   end if;
   n=n+1;
  end loop;
 elsif op='reopen' then
  if period.status is distinct from 'finalized' then raise exception 'No finalized attendance to reopen';end if;
  update payroll_private.attendance_periods set status='draft' where company_id=cid and month=m;
  insert into payroll_private.attendance_period_events(company_id,month,action,actor,reason,snapshot) values(cid,m,'reopen',uid,reason,to_jsonb(period));
 end if;
 if op in ('save','import') then
  insert into payroll_private.attendance_periods(company_id,month) values(cid,m) on conflict do nothing;
 end if;
 rows=payroll_private.attendance_register_rows(cid,m);hash=payroll_private.attendance_period_hash(cid,m);
 select count(*) into issues from jsonb_array_elements(rows) x where (x->>'unresolved')::boolean;
 select count(*) into pending from public.payroll_leaves where company_id=cid and status='submitted' and from_date<(m+interval '1 month')::date and to_date>=m;
 select count(*) into late_pending from public.payroll_staff st cross join lateral (select payroll_private.late_plan(st.id,m) plan) lp
 left join public.payroll_late_reviews lr on lr.staff_id=st.id and lr.company_id=cid and lr.month=m and lr.status='active'
 where st.company_id=cid and st.joining_date<(m+interval '1 month')::date and coalesce(st.leaving_date,'infinity'::date)>=m
 and ((lr.id is not null and lr.source_hash is distinct from lp.plan->>'source_hash') or (lr.id is null and exists(select 1 from jsonb_array_elements(lp.plan->'events') e where not (e->>'covered')::boolean)));
 if op='finalize' then
  if jsonb_array_length(rows)=0 or issues+pending+late_pending>0 then raise exception 'Resolve attendance (%), pending leave (%) and monthly late reviews (%) before finalizing',issues,pending,late_pending;end if;
  insert into payroll_private.attendance_periods(company_id,month,status,source_hash,snapshot,finalized_by,finalized_at) values(cid,m,'finalized',hash,rows,uid,now())
  on conflict(company_id,month) do update set status='finalized',source_hash=excluded.source_hash,snapshot=excluded.snapshot,finalized_by=uid,finalized_at=now();
  insert into payroll_private.attendance_period_events(company_id,month,action,actor,reason,snapshot) values(cid,m,'finalize',uid,reason,jsonb_build_object('source_hash',hash,'rows',rows));
 end if;
 select * into period from payroll_private.attendance_periods where company_id=cid and month=m;
 result=jsonb_build_object('rows',rows,'source_hash',hash,'status',coalesce(period.status,'draft'),'current',period.source_hash=hash,'finalized_at',period.finalized_at,
  'unresolved',issues,'pending_leave',pending,'pending_late',late_pending,'updated',n,
  'history',coalesce((select jsonb_agg(jsonb_build_object('action',e.action,'actor',e.actor,'reason',e.reason,'created_at',e.created_at) order by e.created_at,e.id) from payroll_private.attendance_period_events e where company_id=cid and month=m),'[]'::jsonb));
 if op<>'load' then
  insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,'attendance_register_'||op,m::text);
  insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqtoken,cid,uid,'attendance_register_v1',md5(payload::text),result);
 end if;
 return result;
end$function$
;
