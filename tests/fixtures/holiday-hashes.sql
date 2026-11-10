CREATE OR REPLACE FUNCTION payroll_private.day_punch_hash(cid uuid, sid uuid, d date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select md5(coalesce(jsonb_agg(jsonb_build_array(p.event_time,p.direction,p.manual_entry) order by p.event_time,p.direction,p.id)::text,'[]'))
 from public.payroll_punches p where p.company_id=cid and p.staff_id=sid
 and p.event_time>=d::timestamp at time zone 'Asia/Kolkata' and p.event_time<(d+1)::timestamp at time zone 'Asia/Kolkata'
$function$
;
CREATE OR REPLACE FUNCTION payroll_private.attendance_context_hash(cid uuid, sid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select md5(jsonb_build_array(s.joining_date,s.leaving_date,s.shift_name,s.shift_start,s.shift_end,s.early_grace,c.settings->'working_days',c.settings->'holidays')::text)
 from public.payroll_staff s join public.payroll_companies c on c.id=s.company_id where s.company_id=cid and s.id=sid
$function$
;
