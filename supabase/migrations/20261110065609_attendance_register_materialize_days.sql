-- Compute each day once: downstream fields reuse leave and evidence results.
CREATE OR REPLACE FUNCTION payroll_private.attendance_register_rows(cid uuid, m date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with raw as (
  select p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date work_date,
   jsonb_agg(jsonb_build_object('time',to_char(p.event_time at time zone 'Asia/Kolkata','HH24:MI:SS'),'direction',p.direction,'manual_entry',p.manual_entry) order by p.event_time,p.direction,p.id) punches
  from public.payroll_punches p where p.company_id=cid and p.event_time>=m::timestamp at time zone 'Asia/Kolkata'
   and p.event_time<(m+interval '1 month') at time zone 'Asia/Kolkata' group by p.staff_id,(p.event_time at time zone 'Asia/Kolkata')::date
 ),days as materialized (
  select s.id staff_id,s.name,s.code,s.department,s.shift_start,s.shift_end,s.early_grace,d::date work_date,
   c.settings->'working_days' @> jsonb_build_array(extract(isodow from d)::int) and not c.settings->'holidays' @> jsonb_build_array(d::date::text) working_day,
   to_jsonb(a) attendance,coalesce(raw.punches,'[]'::jsonb) punches,
   case when a.id is null then raw.punches is null else
    (a.punch_hash is not distinct from payroll_private.day_punch_hash(cid,s.id,d::date) or (a.punch_hash is null and raw.punches is null))
    and (a.review_context_hash is null or a.review_context_hash=payroll_private.attendance_context_hash(cid,s.id)) end evidence_current,
   (select jsonb_agg(jsonb_build_object('type',l.leave_type,'half_day',l.half_day,'paid',pol.paid)) from public.payroll_leaves l join public.payroll_leave_policies pol on pol.company_id=l.company_id and pol.code=l.leave_type where l.company_id=cid and l.staff_id=s.id and l.status='approved' and d::date between l.from_date and l.to_date) leaves,
   (select coalesce(sum(0.5),0) from public.payroll_late_reviews lr cross join jsonb_array_elements(lr.decisions) dec join public.payroll_attendance la on la.id=(dec->>'attendance_id')::uuid where lr.company_id=cid and lr.staff_id=s.id and lr.month=m and lr.status='active' and la.work_date=d::date and dec->>'decision'='lop') late_lop
  from public.payroll_staff s join public.payroll_companies c on c.id=s.company_id
  cross join lateral generate_series(greatest(m,s.joining_date),least((m+interval '1 month - 1 day')::date,coalesce(s.leaving_date,'infinity'::date)),interval '1 day') d
  left join public.payroll_attendance a on a.company_id=cid and a.staff_id=s.id and a.work_date=d::date
  left join raw on raw.staff_id=s.id and raw.work_date=d::date
  where s.company_id=cid and s.joining_date<(m+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>=m
 ),review as (
  select *,coalesce(jsonb_array_length(leaves),0)>1 or
   (working_day and (leaves is null or (leaves->0->>'half_day')::boolean) and (attendance is null or attendance->>'reviewed_by' is null or not evidence_current)) or
   (jsonb_array_length(punches)>0 and attendance is not null and not evidence_current) unresolved
  from days
 ),units as (
  select *,case when not working_day then 1
   when leaves is not null and not (leaves->0->>'half_day')::boolean then case when (leaves->0->>'paid')::boolean then 1 else 0 end
   when leaves is not null then case when attendance->>'status'='absent' then case when (leaves->0->>'paid')::boolean then 0.5 else 0 end else case when (leaves->0->>'paid')::boolean then 1 else 0.5 end end
   when attendance->>'status'='absent' then 0 when attendance->>'status'='half_day' then 0.5 else 1 end units
  from review
 ) select coalesce(jsonb_agg(jsonb_build_object('staff_id',staff_id,'work_date',work_date,
  'staff',jsonb_build_object('name',name,'code',code,'department',department,'shift_start',shift_start,'shift_end',shift_end,'early_grace',early_grace),
  'working_day',working_day,'leave',leaves->0,'leave_count',coalesce(jsonb_array_length(leaves),0),
  'attendance',attendance,'punches',punches,'evidence_current',evidence_current,'unresolved',unresolved,
  'paid_days',case when unresolved then null else greatest(0,units-late_lop) end,
  'lop_days',case when unresolved then null else 1-greatest(0,units-late_lop) end
 ) order by work_date,department,name,staff_id),'[]'::jsonb) from units
$function$
;
