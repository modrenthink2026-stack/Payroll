-- Isolated payroll tables. Existing construction tables and Auth settings are unchanged.
create schema if not exists payroll_private;
revoke all on schema payroll_private from public, anon;
grant usage on schema payroll_private to authenticated;

create table public.payroll_companies(id uuid primary key default gen_random_uuid(),name text not null,address text not null default '',settings jsonb not null default '{"working_days":[1,2,3,4,5,6],"holidays":[],"pf_rate":12,"pf_employer_rate":12,"pf_cap":25000,"esi_rate":0.75,"esi_employer_rate":3.25,"statutory_reviewed":false,"effective_from":"2026-10-01","deposit_enabled":false,"deposit_cap":0,"late_grace":10,"early_grace":10,"signatory":""}',created_at timestamptz default now());
create table public.payroll_members(company_id uuid references public.payroll_companies not null,user_id uuid references auth.users not null,role text check(role in ('admin','hr','accountant','manager','staff')) not null,primary key(company_id,user_id));
create table public.payroll_staff(id uuid primary key default gen_random_uuid(),company_id uuid references public.payroll_companies not null,code text not null,name text not null,email text not null,department text not null default '',designation text not null default '',joining_date date not null,leaving_date date,status text not null default 'active' check(status in ('active','separated')),service_status text not null default 'probation',manager_user_id uuid references auth.users,user_id uuid references auth.users,biometric_id text,leave_balances jsonb not null default '{"CL":12,"SL":12,"EL":0}',probation_end date,unique(company_id,code),unique(company_id,email),unique(company_id,biometric_id),unique(company_id,id),check(leaving_date is null or leaving_date>=joining_date));
create table public.payroll_profiles(staff_id uuid primary key references public.payroll_staff,company_id uuid not null,bank_account text default '',ifsc text default '',pan text default '',uan text default '',esi_number text default '',pf_enabled boolean default false,esi_enabled boolean default false,annual_tax numeric(14,2) default 0 check(annual_tax>=0),tax_paid numeric(14,2) default 0 check(tax_paid>=0),other_deductions numeric(14,2) default 0 check(other_deductions>=0),pt numeric(14,2) default 0 check(pt>=0),deposit_eligible boolean default false,foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_salaries(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,effective_from date not null,basic numeric(14,2) not null check(basic>=0),da numeric(14,2) not null default 0 check(da>=0),hra numeric(14,2) not null default 0 check(hra>=0),other numeric(14,2) not null default 0 check(other>=0),approved_by uuid references auth.users,unique(staff_id,effective_from),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_attendance(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,work_date date not null,status text check(status in ('present','absent','half_day','holiday')) not null,in_time time,out_time time,late_minutes int not null default 0 check(late_minutes>=0),early_minutes int not null default 0 check(early_minutes>=0),note text default '',reviewed_by uuid references auth.users,unique(staff_id,work_date),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_punches(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,device_id text not null,event_id text not null,event_time timestamptz not null,direction text not null check(direction in ('in','out')),created_at timestamptz default now(),unique(company_id,device_id,event_id),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_leave_policies(company_id uuid references public.payroll_companies not null,code text not null,annual_entitlement numeric(6,2) not null default 0 check(annual_entitlement>=0),paid boolean not null,description text default '',primary key(company_id,code));
create table public.payroll_leaves(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,leave_type text not null,from_date date not null,to_date date not null,half_day boolean not null default false,units numeric(6,2) not null check(units>0),reason text not null,status text not null default 'submitted' check(status in ('submitted','approved','rejected','cancelled')),created_by uuid references auth.users,reviewed_by uuid references auth.users,created_at timestamptz default now(),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id),foreign key(company_id,leave_type) references public.payroll_leave_policies(company_id,code),check(to_date>=from_date));
create table public.payroll_leave_ledger(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,leave_type text not null,units numeric(6,2) not null,reason text not null,leave_id uuid references public.payroll_leaves,event text not null,created_at timestamptz default now(),unique(leave_id,event),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_documents(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid,type text not null,recipient text not null,body text not null,number text,signatory text not null default '',status text not null default 'draft' check(status in ('draft','approved','issued','acknowledged')),created_by uuid references auth.users,approved_by uuid references auth.users,issued_at timestamptz,effective_date date,created_at timestamptz default now(),unique(company_id,number),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_assessments(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,period text not null,ratings jsonb not null,score numeric(4,2) not null,comments text not null,status text not null default 'finalized',created_by uuid references auth.users,created_at timestamptz default now(),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_increments(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,effective_from date not null,basic numeric(14,2) not null check(basic>=0),da numeric(14,2) not null check(da>=0),hra numeric(14,2) not null check(hra>=0),other numeric(14,2) not null check(other>=0),reason text not null,status text not null default 'recommended' check(status in ('recommended','accountant_reviewed','approved','rejected')),created_by uuid references auth.users,reviewed_by uuid references auth.users,approved_by uuid references auth.users,foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_runs(id uuid primary key default gen_random_uuid(),company_id uuid references public.payroll_companies not null,month date not null,status text not null default 'calculated' check(status in ('calculated','hr_reviewed','accountant_reviewed','locked','released','paid')),created_by uuid references auth.users,hr_by uuid references auth.users,accountant_by uuid references auth.users,authorized_by uuid references auth.users,input_hash text not null,snapshot jsonb not null,created_at timestamptz default now(),unique(company_id,month));
create table public.payroll_lines(staff_snapshot jsonb not null default '{}',deposit_opening numeric(14,2) not null default 0,deposit_closing numeric(14,2) not null default 0,id uuid primary key default gen_random_uuid(),company_id uuid not null,run_id uuid references public.payroll_runs not null,staff_id uuid not null,earnings jsonb not null,deductions jsonb not null,employer jsonb not null,gross numeric(14,2) not null,net numeric(14,2) not null,paid_days numeric(6,2) not null,lop numeric(6,2) not null,issues jsonb not null default '[]',payment_reference text,unique(run_id,staff_id),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_deposits(id uuid primary key default gen_random_uuid(),company_id uuid not null,staff_id uuid not null,amount numeric(14,2) not null,reason text not null,line_id uuid unique references public.payroll_lines,created_by uuid references auth.users,created_at timestamptz default now(),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id));
create table public.payroll_audit(id bigint generated always as identity primary key,company_id uuid references public.payroll_companies,actor uuid references auth.users,action text not null,record_id text,created_at timestamptz default now());

create table payroll_private.requests(token uuid primary key,company_id uuid references public.payroll_companies,user_id uuid references auth.users,operation text not null,request_hash text not null,response jsonb not null,created_at timestamptz default now());
revoke all on payroll_private.requests from public,anon,authenticated;
create unique index payroll_refund_reference_idx on public.payroll_deposits(staff_id,reason) where amount<0;


alter table public.payroll_staff
 add column shift_name text not null default 'General',
 add column shift_start time not null default '09:00',
 add column shift_end time not null default '18:00',
 add column break_minutes int not null default 0 check(break_minutes>=0),
 add column late_grace int not null default 0 check(late_grace between 0 and 1440),
 add column early_grace int not null default 0 check(early_grace between 0 and 1440),
 add constraint payroll_staff_shift_valid check(shift_start<>shift_end and break_minutes < ((extract(epoch from (shift_end-shift_start))::int+86400)%86400)/60);
alter table public.payroll_attendance add column shift_snapshot jsonb;

create function payroll_private.role(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select m.role from public.payroll_members m where m.company_id=cid and m.user_id=auth.uid()
 and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='separated')
 and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=auth.uid() and s.status='active'))
$$;
create function payroll_private.own(sid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.payroll_staff where id=sid and user_id=auth.uid() and status='active' and payroll_private.role(company_id) is not null)$$;
create function payroll_private.team(sid uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.payroll_staff where id=sid and manager_user_id=auth.uid())$$;
-- Monthly whole-incident late allowance, with explicit Principal / HR decisions.
alter table public.payroll_attendance add column raw_late_minutes int check(raw_late_minutes>=0);
alter table public.payroll_lines add column late_summary jsonb not null default '{}';
create table public.payroll_late_reviews(
 id uuid primary key default gen_random_uuid(), company_id uuid not null,staff_id uuid not null,month date not null check(month=date_trunc('month',month)::date),
 source_hash text not null,plan jsonb not null,decisions jsonb not null check(jsonb_typeof(decisions)='array'),cl_units numeric not null check(cl_units>=0),
 status text not null default 'active' check(status in ('active','reopened')),reason text not null,
 reviewed_by uuid not null references auth.users,reviewed_at timestamptz not null default now(),reopened_by uuid references auth.users,reopened_at timestamptz,reopen_reason text,
 foreign key(company_id,staff_id) references public.payroll_staff(company_id,id)
);
create unique index payroll_late_active_idx on public.payroll_late_reviews(company_id,staff_id,month) where status='active';
alter table public.payroll_late_reviews enable row level security;
revoke all on public.payroll_late_reviews from public,anon,authenticated;
grant select on public.payroll_late_reviews to authenticated;
create function payroll_private.late_plan(sid uuid,m date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.payroll_staff;c public.payroll_companies;a record;remaining int=25;used int=0;total int=0;uncovered int=0;events jsonb='[]';h text;
begin
 if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a payroll month';end if;
 select * into s from public.payroll_staff where id=sid;if not found then raise exception 'Staff not found';end if;
 select * into c from public.payroll_companies where id=s.company_id;
 for a in select at.id,at.work_date,to_char(at.in_time,'HH24:MI') as in_time,coalesce(left(at.shift_snapshot->>'start',5),to_char(s.shift_start,'HH24:MI')) as reporting_time,coalesce(at.raw_late_minutes,at.late_minutes) as mins from public.payroll_attendance at
 where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date
 and at.work_date>=s.joining_date and at.work_date<=coalesce(s.leaving_date,'infinity'::date) and at.status='present'
 and coalesce(at.raw_late_minutes,at.late_minutes)>0
 and c.settings->'working_days' @> jsonb_build_array(extract(isodow from at.work_date)::int)
 and not c.settings->'holidays' @> jsonb_build_array(at.work_date::text)
 and not exists(select 1 from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and at.work_date between l.from_date and l.to_date)
 order by coalesce(at.raw_late_minutes,at.late_minutes),at.work_date,at.id loop
  total=total+a.mins;
  if a.mins<=remaining then remaining=remaining-a.mins;used=used+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'minutes',a.mins,'cumulative_minutes',total,'covered',true));
  else uncovered=uncovered+a.mins;
   events=events||jsonb_build_array(jsonb_build_object('attendance_id',a.id,'date',a.work_date,'day',trim(to_char(a.work_date,'Day')),'reporting_time',a.reporting_time,'in_time',a.in_time,'minutes',a.mins,'cumulative_minutes',total,'covered',false));
  end if;
 end loop;
 h=md5(jsonb_build_array(m,25,s.id,s.joining_date,s.leaving_date,c.settings->'working_days',c.settings->'holidays',
 (select jsonb_agg(to_jsonb(at) order by at.work_date,at.id) from public.payroll_attendance at where at.staff_id=sid and at.work_date>=m and at.work_date<(m+interval '1 month')::date),
 (select jsonb_agg(jsonb_build_array(l.id,l.from_date,l.to_date,l.half_day,l.leave_type) order by l.id) from public.payroll_leaves l where l.staff_id=sid and l.status='approved' and l.to_date>=m and l.from_date<(m+interval '1 month')::date))::text);
 return jsonb_build_object('month',m,'allowance',25,'total_minutes',total,'used_minutes',used,'unused_minutes',remaining,'net_excess_minutes',greatest(0,total-25),'uncovered_minutes',uncovered,'events',events,'source_hash',h);
end$$;
revoke all on function payroll_private.late_plan(uuid,date) from public,anon,authenticated;

create function payroll_private.fingerprint(cid uuid) returns text language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_array(
 (select to_jsonb(c) from public.payroll_companies c where id=cid),
 (select jsonb_agg(s order by id) from public.payroll_staff s where company_id=cid),
 (select jsonb_agg(p order by staff_id) from public.payroll_profiles p where company_id=cid),
 (select jsonb_agg(s order by id) from public.payroll_salaries s where company_id=cid),
 (select jsonb_agg(a order by id) from public.payroll_attendance a where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_leaves l where company_id=cid),
 (select jsonb_agg(d order by id) from public.payroll_deposits d where company_id=cid),
 (select jsonb_agg(p order by code) from public.payroll_leave_policies p where company_id=cid),
 (select jsonb_agg(l order by id) from public.payroll_late_reviews l where company_id=cid))::text)
$$;

do $$declare t text;begin
 foreach t in array array['companies','members','staff','profiles','salaries','attendance','punches','leave_policies','leaves','leave_ledger','documents','assessments','increments','runs','lines','deposits','audit'] loop
  execute format('alter table public.payroll_%I enable row level security',t);
  execute format('revoke all on public.payroll_%I from anon, authenticated',t);
  execute format('grant select on public.payroll_%I to authenticated',t);
 end loop;
end$$;
create policy companies_read on public.payroll_companies for select to authenticated using(payroll_private.role(id) is not null);
create policy members_read on public.payroll_members for select to authenticated using(user_id=auth.uid() or payroll_private.role(company_id)='admin');
create policy staff_read on public.payroll_staff for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(id) or (payroll_private.role(company_id)='manager' and payroll_private.team(id)));
create policy profiles_read on public.payroll_profiles for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id));
create policy salaries_read on public.payroll_salaries for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id));
create policy attendance_read on public.payroll_attendance for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id) or (payroll_private.role(company_id)='manager' and payroll_private.team(staff_id)));
create policy punches_read on public.payroll_punches for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id));
create policy policies_read on public.payroll_leave_policies for select to authenticated using(payroll_private.role(company_id) is not null);
create policy leaves_read on public.payroll_leaves for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id) or (payroll_private.role(company_id)='manager' and payroll_private.team(staff_id)));
create policy leave_ledger_read on public.payroll_leave_ledger for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id));
create policy documents_read on public.payroll_documents for select to authenticated using(payroll_private.role(company_id) in ('admin','hr') or (payroll_private.own(staff_id) and status in ('issued','acknowledged')));
create policy assessments_read on public.payroll_assessments for select to authenticated using(payroll_private.role(company_id) in ('admin','hr') or payroll_private.own(staff_id) or (payroll_private.role(company_id)='manager' and payroll_private.team(staff_id)));
create policy increments_read on public.payroll_increments for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or (payroll_private.own(staff_id) and status='approved'));
create policy runs_read on public.payroll_runs for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or (payroll_private.role(company_id)='staff' and status in ('released','paid')));
create policy lines_read on public.payroll_lines for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or (payroll_private.own(staff_id) and exists(select 1 from public.payroll_runs r where r.id=run_id and r.status in ('released','paid'))));
create policy deposits_read on public.payroll_deposits for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id));
create policy audit_read on public.payroll_audit for select to authenticated using(payroll_private.role(company_id)='admin');

alter table public.payroll_staff alter column email drop not null;
alter table public.payroll_staff add column erp_code text not null default '', add column employment_status text not null default '', add column employment_category text not null default '';
create table public.payroll_staff_details (
 staff_id uuid primary key, company_id uuid not null, details jsonb not null default '{}' check(jsonb_typeof(details)='object'),
 source_records jsonb not null default '[]' check(jsonb_typeof(source_records)='array'),
 foreign key(company_id,staff_id) references public.payroll_staff(company_id,id) on delete cascade
);
alter table public.payroll_staff_details enable row level security;
revoke all on public.payroll_staff_details from public,anon,authenticated;
grant select on public.payroll_staff_details to authenticated;
create policy staff_details_read on public.payroll_staff_details for select to authenticated using(payroll_private.role(company_id) in ('admin','hr') or payroll_private.own(staff_id));

create function payroll_private.calculate(cid uuid,month_start date) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.payroll_companies; s public.payroll_staff; p public.payroll_profiles; sal public.payroll_salaries; att public.payroll_attendance;
 day date; last_day date; rid uuid; ndays int; remaining int; factor numeric; units numeric; lop numeric; paid numeric;
 b numeric; da numeric; hra numeric; other numeric; gross numeric; pf numeric; esi numeric; tds numeric; deposit numeric; balance numeric; wage numeric; deductions numeric;
 issues jsonb; lr public.payroll_leaves; is_work boolean; lrpaid boolean; late_plan jsonb;late_review public.payroll_late_reviews;late_valid boolean;late_lop numeric;
begin
 select * into c from public.payroll_companies where id=cid for update;
 if not coalesce((c.settings->>'statutory_reviewed')::boolean,false) then raise exception 'Accountant must review statutory settings before payroll calculation';end if;
 if month_start<>date_trunc('month',month_start)::date then raise exception 'Select a month';end if;
 if (c.settings->>'effective_from')::date>month_start then raise exception 'These statutory settings do not cover that payroll month';end if;
 last_day=(month_start+interval '1 month - 1 day')::date;ndays=extract(day from last_day);
 remaining=case when extract(month from month_start)>=4 then 16-extract(month from month_start)::int else 4-extract(month from month_start)::int end;
 select id into rid from public.payroll_runs where company_id=cid and month=month_start for update;
 if rid is not null then
  if exists(select 1 from public.payroll_runs where id=rid and status not in ('calculated','hr_reviewed','accountant_reviewed')) then raise exception 'Locked payroll cannot be recalculated';end if;
  delete from public.payroll_lines where run_id=rid;
  update public.payroll_runs set status='calculated',created_by=auth.uid(),hr_by=null,accountant_by=null,authorized_by=null,input_hash=payroll_private.fingerprint(cid),snapshot=to_jsonb(c) where id=rid;
 else insert into public.payroll_runs(company_id,month,created_by,input_hash,snapshot) values(cid,month_start,auth.uid(),payroll_private.fingerprint(cid),to_jsonb(c)) returning id into rid;end if;
 for s in select * from public.payroll_staff where company_id=cid and joining_date<=last_day and (leaving_date is null or leaving_date>=month_start) loop
  select * into p from public.payroll_profiles where staff_id=s.id;
  b=0;da=0;hra=0;other=0;lop=0;paid=0;issues='[]';
  late_plan=payroll_private.late_plan(s.id,month_start);
  select * into late_review from public.payroll_late_reviews where staff_id=s.id and month=month_start and status='active';
  late_valid=found and late_review.source_hash=late_plan->>'source_hash';
  if late_review.id is not null and not late_valid then issues=issues||jsonb_build_array('Late review inputs changed; reopen and review this month');
  elsif not late_valid and exists(select 1 from jsonb_array_elements(late_plan->'events') e where not (e->>'covered')::boolean) then issues=issues||jsonb_build_array('Principal / HR monthly late decision required');end if;
  for day in select generate_series(greatest(month_start,s.joining_date),least(last_day,coalesce(s.leaving_date,last_day)),interval '1 day')::date loop
   select * into sal from public.payroll_salaries where staff_id=s.id and effective_from<=day order by effective_from desc limit 1;
   if not found then issues=issues||jsonb_build_array('No salary version for '||day);continue;end if;
   is_work=(c.settings->'working_days') @> jsonb_build_array(extract(isodow from day)::int) and not (c.settings->'holidays') @> jsonb_build_array(day::text);
   select l.* into lr from public.payroll_leaves l where l.staff_id=s.id and status='approved' and day between from_date and to_date limit 1;
   units=1;
   if found and is_work then
    select pol.paid into lrpaid from public.payroll_leave_policies pol where pol.company_id=cid and pol.code=lr.leave_type;
    if not lrpaid then
     units=case when lr.half_day then 0.5 else 0 end;
     if lr.half_day then
      select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
      if not found then issues=issues||jsonb_build_array('Review remaining half-day: '||day);
      elsif att.status='absent' then units=0;end if;
     end if;
    elsif lr.half_day then
     select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
     if not found then issues=issues||jsonb_build_array('Review remaining half-day: '||day);
     elsif att.status='absent' then units=0.5;end if;
    end if;
   elsif is_work then
    select * into att from public.payroll_attendance where staff_id=s.id and work_date=day;
    if not found then issues=issues||jsonb_build_array('Attendance not reviewed: '||day);
    elsif att.status='absent' then units=0;
    elsif att.status='half_day' then units=0.5;end if;
   end if;
   if late_valid then
    select coalesce(sum(0.5),0) into late_lop from jsonb_array_elements(late_review.decisions) d join public.payroll_attendance a on a.id=(d->>'attendance_id')::uuid where a.work_date=day and d->>'decision'='lop';
    units=greatest(0,units-late_lop);
   end if;
   factor=units/ndays;paid=paid+units;lop=lop+(1-units);
   b=b+sal.basic*factor;da=da+sal.da*factor;hra=hra+sal.hra*factor;other=other+sal.other*factor;
  end loop;
  b=round(b,2);da=round(da,2);hra=round(hra,2);other=round(other,2);gross=b+da+hra+other;
  -- Reviewed statutory wage model: Basic+DA plus exclusion add-back. Employer must confirm suitability.
  wage=greatest(b+da,gross/2);
  pf=case when p.pf_enabled then round(least(wage,(c.settings->>'pf_cap')::numeric)*(c.settings->>'pf_rate')::numeric/100) else 0 end;
  esi=case when p.esi_enabled then ceil(wage*(c.settings->>'esi_rate')::numeric/100) else 0 end;
  tds=round(greatest(0,p.annual_tax-p.tax_paid)/remaining,2);
  select coalesce(sum(amount),0) into balance from public.payroll_deposits where staff_id=s.id;
  deposit=case when p.deposit_eligible and coalesce((c.settings->>'deposit_enabled')::boolean,false) then round(least(gross*0.10,greatest(0,(c.settings->>'deposit_cap')::numeric-balance)),2) else 0 end;
  deductions=pf+esi+tds+deposit+coalesce(p.other_deductions,0)+coalesce(p.pt,0);
  if deductions>wage/2 then issues=issues||jsonb_build_array('Deductions exceed the conservative 50% reviewed-wage limit');end if;
  if deductions>gross then issues=issues||jsonb_build_array('Negative net pay');end if;
  insert into public.payroll_lines(staff_snapshot,deposit_opening,deposit_closing,company_id,run_id,staff_id,earnings,deductions,employer,gross,net,paid_days,lop,issues)
  values(to_jsonb(s),balance,balance+deposit,cid,rid,s.id,jsonb_build_object('Basic',b,'DA',da,'HRA',hra,'Other allowance',other),
  jsonb_build_object('PF',pf,'ESI',esi,'TDS',tds,'Security deposit',deposit,'Other deduction',coalesce(p.other_deductions,0),'PT',coalesce(p.pt,0)),
  jsonb_build_object('PF total',case when p.pf_enabled then round(least(wage,(c.settings->>'pf_cap')::numeric)*(c.settings->>'pf_employer_rate')::numeric/100) else 0 end,'ESI',case when p.esi_enabled then ceil(wage*(c.settings->>'esi_employer_rate')::numeric/100) else 0 end),gross,gross-deductions,paid,lop,issues);
  update public.payroll_lines set late_summary=late_plan-'events'-'source_hash'||jsonb_build_object('review_id',late_review.id,'review_valid',late_valid,'cl_days',case when late_valid then late_review.cl_units else 0 end,'lop_days',case when late_valid then (select count(*)*0.5 from jsonb_array_elements(late_review.decisions) d where d->>'decision'='lop') else 0 end) where run_id=rid and staff_id=s.id;
 end loop;
 if not exists(select 1 from public.payroll_lines where run_id=rid) then raise exception 'Add staff and salary details first';end if;
 return rid;
end$$;

-- Company-scoped leave approval offices. No payroll role is granted by a title.
alter table public.payroll_staff add column leave_group text check(leave_group in ('teacher_staff','principal','director','support','president'));
alter table public.payroll_leaves add column approval_office text check(approval_office in ('principal','director','president','hr'));
create table public.payroll_leave_approvers(
 company_id uuid not null references public.payroll_companies,
 office text not null check(office in ('principal','director','president','hr')),
 user_id uuid, updated_by uuid references auth.users, updated_at timestamptz not null default now(),
 primary key(company_id,office),foreign key(company_id,user_id) references public.payroll_members(company_id,user_id)
);
alter table public.payroll_leave_approvers enable row level security;
revoke all on public.payroll_leave_approvers from public,anon,authenticated;
grant select on public.payroll_leave_approvers to authenticated;
create policy leave_approvers_read on public.payroll_leave_approvers for select to authenticated using(payroll_private.role(company_id)='admin');
create index payroll_leave_approvers_user_idx on public.payroll_leave_approvers(user_id);
create function payroll_private.leave_group(explicit_group text,designation text,department text,category text) returns text language sql immutable set search_path='' as $$
 select coalesce(explicit_group,case
 when lower(trim(designation))='principal' then 'principal'
 when lower(trim(designation))='director' then 'director'
 when lower(trim(designation))='president' then 'president'
 when lower(concat_ws(' ',designation,department,category)) ~ '(^|[^a-z])(sub[ -]?staff|aayahs?|ayahs?|aayas?|aayas|attenders?|attendants?|security|securty|watchman|watchmen)([^a-z]|$)' then 'support'
 else 'teacher_staff' end)
$$;
create function payroll_private.leave_office(sid uuid) returns text language sql stable security definer set search_path='' as $$
 select case payroll_private.leave_group(s.leave_group,s.designation,s.department,s.employment_category)
 when 'teacher_staff' then 'principal' when 'principal' then 'director' when 'director' then 'president' when 'support' then 'hr' end
 from public.payroll_staff s where s.id=sid
$$;
create function payroll_private.leave_can_decide(lid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_leaves l join public.payroll_staff s on s.id=l.staff_id
 join public.payroll_leave_approvers a on a.company_id=l.company_id and a.office=coalesce(l.approval_office,payroll_private.leave_office(l.staff_id))
 where l.id=lid and a.user_id=auth.uid() and payroll_private.role(l.company_id) is not null
 and l.created_by is distinct from auth.uid() and s.user_id is distinct from auth.uid() and s.status='active')
$$;
revoke all on function payroll_private.leave_group(text,text,text,text),payroll_private.leave_office(uuid),payroll_private.leave_can_decide(uuid) from public,anon,authenticated;
grant execute on function payroll_private.leave_can_decide(uuid) to authenticated;
drop policy leaves_read on public.payroll_leaves;
create policy leaves_read on public.payroll_leaves for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id) or payroll_private.leave_can_decide(id));

create function payroll_private.late_can_review(sid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payroll_staff s where s.id=sid and s.user_id is distinct from auth.uid()
 and payroll_private.role(s.company_id) is not null and exists(select 1 from public.payroll_leave_approvers a where a.company_id=s.company_id and a.office in ('principal','hr') and a.user_id=auth.uid()))
$$;
revoke all on function payroll_private.late_can_review(uuid) from public,anon,authenticated;
grant execute on function payroll_private.late_can_review(uuid) to authenticated;
create policy late_reviews_read on public.payroll_late_reviews for select to authenticated using(payroll_private.role(company_id) in ('admin','hr','accountant') or payroll_private.own(staff_id) or payroll_private.late_can_review(staff_id));

create function payroll_private.dispatch(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid=auth.uid(); cid uuid=nullif(payload->>'company_id','')::uuid; r text; sid uuid=nullif(payload->>'staff_id','')::uuid; rec uuid=nullif(payload->>'id','')::uuid;
 c public.payroll_companies; st public.payroll_staff; le public.payroll_leaves; late_review public.payroll_late_reviews; late_plan jsonb; m date; cl_days numeric; doc public.payroll_documents; inc public.payroll_increments; run public.payroll_runs;
 v_email text; target_uid uuid; reqid uuid=nullif(payload->>'request_id','')::uuid; j jsonb; day date; units numeric; reserved numeric; balance numeric; paid_type boolean; out jsonb; score numeric;
begin
 if uid is null then raise exception 'Authentication required';end if;
 if not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirm your email before accessing payroll';end if;
 if action='bootstrap' then
  select lower(u.email) into v_email from auth.users u where id=uid;
  for st in select * from public.payroll_staff where lower(payroll_staff.email)=v_email and status='active' and (user_id is null or user_id=uid) loop
   update public.payroll_staff set user_id=uid where id=st.id;
   insert into public.payroll_members(company_id,user_id,role) values(st.company_id,uid,'staff') on conflict do nothing;
  end loop;
  return jsonb_build_object('companies',coalesce((select jsonb_agg(to_jsonb(co)||jsonb_build_object('role',m.role)) from public.payroll_companies co join public.payroll_members m on m.company_id=co.id where m.user_id=uid and payroll_private.role(co.id) is not null),'[]'::jsonb));
 end if;
 if action='company_create' then
  if not exists(select 1 from public.payroll_members where user_id=uid and payroll_private.role(company_id)='admin') then raise exception 'Administrator access required';end if;
  insert into public.payroll_companies(name,address) values(nullif(trim(payload->>'name'),''),coalesce(payload->>'address','')) returning id into cid;
  insert into public.payroll_members values(cid,uid,'admin');
  insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid) values(cid,'CL',12,true),(cid,'SL',12,true),(cid,'EL',0,true),(cid,'LWP',0,false);
  return jsonb_build_object('id',cid);
 end if;
 r=payroll_private.role(cid);
 if r is null then raise exception 'No access to this company';end if;
 if action='late_month' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a month';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('staff_id',s.id,'code',s.code,'name',s.name,'can_review',payroll_private.late_can_review(s.id),'plan',payroll_private.late_plan(s.id,m),'review',(select to_jsonb(l) from public.payroll_late_reviews l where l.staff_id=s.id and l.month=m and l.status='active')) order by s.code) from public.payroll_staff s where s.company_id=cid and s.joining_date<(m+interval '1 month')::date and coalesce(s.leaving_date,'infinity'::date)>=m and (r in ('admin','hr','accountant') or payroll_private.own(s.id) or payroll_private.late_can_review(s.id))),'[]'::jsonb);
 end if;
 if action='attendance_report' then
  return coalesce((select jsonb_agg(a order by work_date,staff_id) from public.payroll_attendance a where company_id=cid and work_date>=date_trunc('month',(payload->>'month')::date)::date and work_date<(date_trunc('month',(payload->>'month')::date)+interval '1 month')::date and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id)))),'[]'::jsonb);
 end if;
 if action='state' then
  return jsonb_build_object(
   'staff',coalesce((select jsonb_agg(s order by code) from public.payroll_staff s where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(id) or (r='manager' and payroll_private.team(id)))),'[]'::jsonb),
   'staff_details',coalesce((select jsonb_agg(d) from public.payroll_staff_details d where company_id=cid and (r in ('admin','hr') or payroll_private.own(staff_id))),'[]'::jsonb),
   'profiles',coalesce((select jsonb_agg(p) from public.payroll_profiles p where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'salaries',coalesce((select jsonb_agg(s order by effective_from) from public.payroll_salaries s where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'attendance',coalesce((select jsonb_agg(a) from (select * from public.payroll_attendance where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id))) order by work_date desc,id limit 2000)a),'[]'::jsonb),
   'punches',coalesce((select jsonb_agg(p) from (select * from public.payroll_punches where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id)) order by event_time desc limit 500) p),'[]'::jsonb),
   'policies',coalesce((select jsonb_agg(p) from public.payroll_leave_policies p where company_id=cid),'[]'::jsonb),
   'leave_routing',jsonb_build_object('offices',coalesce((select jsonb_agg(jsonb_build_object('office',a.office,'ready',a.user_id is not null and payroll_private.role(cid) is not null and exists(select 1 from public.payroll_members m where m.company_id=cid and m.user_id=a.user_id and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='separated') and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='active'))))) from public.payroll_leave_approvers a where a.company_id=cid),'[]'::jsonb),'approvers',case when r='admin' then coalesce((select jsonb_agg(jsonb_build_object('office',a.office,'email',u.email)) from public.payroll_leave_approvers a left join auth.users u on u.id=a.user_id where a.company_id=cid),'[]'::jsonb) else '[]'::jsonb end),
   'leaves',coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('staff_name',(select s.name from public.payroll_staff s where s.id=l.staff_id),'approval_office',coalesce(l.approval_office,payroll_private.leave_office(l.staff_id)),'can_decide',payroll_private.leave_can_decide(l.id)) order by created_at desc) from public.payroll_leaves l where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id) or payroll_private.leave_can_decide(id))),'[]'::jsonb),
   'documents',coalesce((select jsonb_agg(d order by created_at desc) from public.payroll_documents d where company_id=cid and (r in ('admin','hr') or (payroll_private.own(staff_id) and status in ('issued','acknowledged')))),'[]'::jsonb),
   'assessments',coalesce((select jsonb_agg(a order by created_at desc) from public.payroll_assessments a where company_id=cid and (r in ('admin','hr') or payroll_private.own(staff_id) or (r='manager' and payroll_private.team(staff_id)))),'[]'::jsonb),
   'increments',coalesce((select jsonb_agg(i) from public.payroll_increments i where company_id=cid and (r in ('admin','hr','accountant') or (payroll_private.own(staff_id) and status='approved'))),'[]'::jsonb),
   'runs',coalesce((select jsonb_agg(p order by month desc) from public.payroll_runs p where company_id=cid and (r in ('admin','hr','accountant') or (r='staff' and status in ('released','paid')))),'[]'::jsonb),
   'lines',coalesce((select jsonb_agg(l) from public.payroll_lines l where company_id=cid and (r in ('admin','hr','accountant') or (payroll_private.own(staff_id) and exists(select 1 from public.payroll_runs where id=l.run_id and status in ('released','paid'))))),'[]'::jsonb),
   'deposits',coalesce((select jsonb_agg(d order by created_at) from public.payroll_deposits d where company_id=cid and (r in ('admin','hr','accountant') or payroll_private.own(staff_id))),'[]'::jsonb),
   'audit',case when r='admin' then coalesce((select jsonb_agg(a) from (select * from public.payroll_audit where company_id=cid order by id desc limit 50)a),'[]'::jsonb) else '[]'::jsonb end);
 end if;
 -- Lock company first for all writes. This serializes payroll locking with staff/leave/input edits.
 select * into c from public.payroll_companies where id=cid for update;
 if reqid is not null then
  select response into out from payroll_private.requests where token=reqid and user_id=uid and company_id=cid and operation=action;
  if found then
   if not exists(select 1 from payroll_private.requests where token=reqid and request_hash=md5(payload::text)) then raise exception 'Request ID reused with different data';end if;
   return out;end if;
  if exists(select 1 from payroll_private.requests where token=reqid) then raise exception 'Request ID collision';end if;
 end if;
 if sid is not null then select * into st from public.payroll_staff where id=sid and company_id=cid for update;if not found then raise exception 'Staff not found in this company';end if;end if;
 if action in ('late_review','late_reopen') then
  if sid is null or not payroll_private.late_can_review(sid) then raise exception 'Assigned Principal / HR approval required; self-review is forbidden';end if;
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Select a month';end if;
  if length(trim(coalesce(payload->>'reason','')))<3 then raise exception 'Enter a review reason';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month=m and status in ('locked','released','paid')) then raise exception 'Payroll month is locked; use the adjustment process';end if;
  select * into late_review from public.payroll_late_reviews where staff_id=sid and month=m and status='active' for update;
  if action='late_reopen' then
   if late_review.id is null then raise exception 'No active late review to reopen';end if;
   if late_review.cl_units>0 then
    update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array['CL'],to_jsonb(coalesce((leave_balances->>'CL')::numeric,0)+late_review.cl_units)) where id=sid;
    insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,'CL',late_review.cl_units,'Reopened late review '||late_review.id,'late_cl_refund');
   end if;
   update public.payroll_late_reviews set status='reopened',reopened_by=uid,reopened_at=now(),reopen_reason=trim(payload->>'reason') where id=late_review.id;rec=late_review.id;
  else
   if late_review.id is not null then raise exception 'Reopen the existing late review before changing decisions';end if;
   late_plan=payroll_private.late_plan(sid,m);
   if payload->>'source_hash' is distinct from late_plan->>'source_hash' then raise exception 'Attendance or leave changed; reload the monthly late report';end if;
   if jsonb_typeof(payload->'decisions') is distinct from 'array' then raise exception 'Review every uncovered late arrival';end if;
   if jsonb_array_length(payload->'decisions')<>(select count(*) from jsonb_array_elements(late_plan->'events') e where not (e->>'covered')::boolean) or jsonb_array_length(payload->'decisions')=0 then raise exception 'Review every uncovered late arrival exactly once';end if;
   if (select count(distinct d->>'attendance_id') from jsonb_array_elements(payload->'decisions') d)<>jsonb_array_length(payload->'decisions') then raise exception 'Duplicate late decision';end if;
   for j in select * from jsonb_array_elements(payload->'decisions') loop
    if coalesce(j->>'decision','') not in ('lop','cl') or not exists(select 1 from jsonb_array_elements(late_plan->'events') e where e->>'attendance_id'=j->>'attendance_id' and not (e->>'covered')::boolean) then raise exception 'Invalid late decision';end if;
   end loop;
   select count(*)*0.5 into cl_days from jsonb_array_elements(payload->'decisions') d where d->>'decision'='cl';
   if cl_days>0 then
    if not exists(select 1 from public.payroll_leave_policies where company_id=cid and code='CL' and paid) then raise exception 'A paid CL policy is required';end if;
    select coalesce(sum(l.units),0) into reserved from public.payroll_leaves l where l.staff_id=sid and l.leave_type='CL' and l.status='submitted';
    if coalesce((st.leave_balances->>'CL')::numeric,0)-reserved<cl_days then raise exception 'Insufficient unreserved Casual Leave balance';end if;
   end if;
   insert into public.payroll_late_reviews(company_id,staff_id,month,source_hash,plan,decisions,cl_units,reason,reviewed_by) values(cid,sid,m,late_plan->>'source_hash',late_plan,payload->'decisions',cl_days,trim(payload->>'reason'),uid) returning id into rec;
   if cl_days>0 then
    update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array['CL'],to_jsonb(coalesce((leave_balances->>'CL')::numeric,0)-cl_days)) where id=sid;
    insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,'CL',-cl_days,'Late review '||rec,'late_cl_debit');
   end if;
  end if;
 elsif action='leave_approver_set' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  if coalesce(payload->>'office','') not in ('principal','director','president','hr') then raise exception 'Choose a valid approval office';end if;
  target_uid=null;
  if nullif(trim(payload->>'email'),'') is not null then
   select u.id into target_uid from auth.users u join public.payroll_members m on m.user_id=u.id and m.company_id=cid
   where lower(u.email)=lower(trim(payload->>'email')) and u.email_confirmed_at is not null
   and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=u.id and s.status='separated')
   and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=u.id and s.status='active'));
   if target_uid is null then raise exception 'Approver needs a confirmed, active account in this company';end if;
  end if;
  insert into public.payroll_leave_approvers(company_id,office,user_id,updated_by) values(cid,payload->>'office',target_uid,uid)
  on conflict(company_id,office) do update set user_id=excluded.user_id,updated_by=excluded.updated_by,updated_at=now();
 elsif action='leave_group_set' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null then raise exception 'Choose a staff member';end if;
  if coalesce(payload->>'leave_group','') not in ('auto','teacher_staff','principal','director','support','president') then raise exception 'Choose a valid leave group';end if;
  update public.payroll_staff set leave_group=nullif(payload->>'leave_group','auto') where id=sid;
 elsif action='settings' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  j=payload->'settings';
  if not j ?& array['working_days','holidays','pf_rate','pf_employer_rate','pf_cap','esi_rate','esi_employer_rate','effective_from','deposit_cap','deposit_enabled','statutory_reviewed'] then raise exception 'Missing required policy settings';end if;
  if jsonb_typeof(j->'working_days')<>'array' or jsonb_array_length(j->'working_days')=0 then raise exception 'Set working weekdays';end if;
  if (j->>'pf_rate')::numeric not between 0 and 100 or (j->>'pf_employer_rate')::numeric not between 0 and 100 or (j->>'esi_rate')::numeric not between 0 and 100 or (j->>'esi_employer_rate')::numeric not between 0 and 100 or (j->>'pf_cap')::numeric<0 or (j->>'deposit_cap')::numeric<0 then raise exception 'Invalid rates or caps';end if;
  if (j->>'deposit_enabled')::boolean and ((j->>'deposit_cap')::numeric<=0 or length(coalesce(j->>'deposit_policy',''))<15) then raise exception 'Set a positive deposit cap and reviewed policy reference';end if;
  update public.payroll_companies set name=nullif(trim(payload->>'name'),''),address=coalesce(payload->>'address',''),settings=j where id=cid;
 elsif action='member_grant' then
  if r<>'admin' then raise exception 'Administrator access required';end if;
  select id into target_uid from auth.users where lower(auth.users.email)=lower(payload->>'email') and email_confirmed_at is not null;
  if target_uid is null then raise exception 'This email must first have a confirmed Supabase account';end if;
  if target_uid=uid then raise exception 'Cannot change your own administrator role';end if;
  if payload->>'role'='staff' and not exists(select 1 from public.payroll_staff where company_id=cid and lower(payroll_staff.email)=lower(payload->>'email') and status='active') then raise exception 'Create the staff master first';end if;
  insert into public.payroll_members values(cid,target_uid,payload->>'role') on conflict(company_id,user_id) do update set role=excluded.role;
 elsif action='staff_roster_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Import 1 to 500 staff rows';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   if nullif(trim(j->>'code'),'') is null or nullif(trim(j->>'name'),'') is null or nullif(j->>'joining_date','') is null then raise exception 'Staff code, name and joining date are required';end if;
   if exists(select 1 from public.payroll_staff where company_id=cid and lower(code)=lower(trim(j->>'code'))) then raise exception 'Staff code already exists';end if;
   if jsonb_typeof(j->'personal_details') is distinct from 'object' or jsonb_typeof(j->'source_records') is distinct from 'array' then raise exception 'Invalid personnel details';end if;
   if exists(select 1 from jsonb_object_keys(j->'personal_details') k where not (k=ANY(array['S NO','Staff Name','Staff Code','Biometric Code','Staff ERPCode','Staff Department Name','Date Of Birth','Sex','Marital Status','Marriage Anniversary','Email','Alternate Email','Mobile No','Alternate No','Emergency No','Whatsapp No','Father Name','Father Occupation','Father PhoneNo','Spouse Name','Spouse PhoneNo','Spouse Ocupation','Address','Landmark1','Landmark2','Country Name','State Name','City Name','AdhaarCard No','PANCard No','Passport No','Government ID','Caste','Sub Caste','Nationality','CitizenShip','Religion','BloodGroup','Bank Name','Bank AccountNo','EPFNo','UAN','ESINo','Bank BranchName','Bank CityName','Bank StateName','Staff Payroll Entity','IFSCCode','Designation','Specialization','Qualification','CTET Qualified','Trained As','Date Of Joining','Date Of InActive','Employment Status','Previous Experience','Experience','Total Experience','Previous InstitutionName','Previous Designation','Security Deposit','Date','Payment Mode','Remarks','UserType Name','AccessLevel','IsDivorced','MotherName','Employment Category','BED Course','Subjects Assigned','NameAsPerBank']::text[]))) then raise exception 'Unknown personnel field';end if;
   insert into public.payroll_staff(company_id,code,name,email,department,designation,joining_date,leaving_date,status,service_status,biometric_id,leave_balances,erp_code,employment_status,employment_category)
   values(cid,trim(j->>'code'),trim(j->>'name'),null,coalesce(j->>'department',''),coalesce(j->>'designation',''),(j->>'joining_date')::date,nullif(j->>'leaving_date','')::date,
    case when nullif(j->>'leaving_date','')::date<=current_date then 'separated' else 'active' end,'imported',nullif(j->>'biometric_id',''),'{}',coalesce(j->'personal_details'->>'Staff ERPCode',''),coalesce(j->'personal_details'->>'Employment Status',''),coalesce(j->'personal_details'->>'Employment Category','')) returning id into sid;
   insert into public.payroll_profiles(staff_id,company_id,bank_account,ifsc,pan,uan,esi_number) values(sid,cid,coalesce(j->>'bank_account',''),coalesce(j->>'ifsc',''),coalesce(j->>'pan',''),coalesce(j->>'uan',''),coalesce(j->>'esi_number',''));
   insert into public.payroll_staff_details(staff_id,company_id,details,source_records) values(sid,cid,j->'personal_details',j->'source_records');
   units=units+1;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='staff_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_typeof(payload->'rows') is distinct from 'array' or jsonb_array_length(payload->'rows') not between 1 and 500 then raise exception 'Import 1 to 500 staff rows';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   perform payroll_private.dispatch('staff_save',(j - 'staff_id' - 'id' - 'request_id')||jsonb_build_object('company_id',cid,'staff_id',null,'request_id',null));
   units=units+1;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='staff_delete' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null or payload->>'confirm_code' is distinct from st.code then raise exception 'Confirm the staff code';end if;
  if st.user_id is not null then raise exception 'Linked staff cannot be deleted; use authorized separation to retain history';end if;
  if exists(select 1 from public.payroll_attendance where staff_id=sid) or exists(select 1 from public.payroll_punches where staff_id=sid)
   or exists(select 1 from public.payroll_leaves where staff_id=sid) or exists(select 1 from public.payroll_leave_ledger where staff_id=sid)
   or exists(select 1 from public.payroll_lines where staff_id=sid) or exists(select 1 from public.payroll_deposits where staff_id=sid)
   or exists(select 1 from public.payroll_documents where staff_id=sid) or exists(select 1 from public.payroll_assessments where staff_id=sid)
   or exists(select 1 from public.payroll_increments where staff_id=sid)
   or (select count(*) from public.payroll_salaries where staff_id=sid)>1
  then raise exception 'Staff has history and cannot be deleted; use authorized separation';end if;
  delete from public.payroll_profiles where staff_id=sid;
  delete from public.payroll_salaries where staff_id=sid;
  delete from public.payroll_staff where id=sid and company_id=cid;
 elsif action='staff_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if nullif(trim(payload->>'code'),'') is null or nullif(trim(payload->>'name'),'') is null or nullif(payload->>'joining_date','') is null then raise exception 'Code, name and joining date are required';end if;
  if sid is null and exists(select 1 from public.payroll_staff where company_id=cid and (lower(code)=lower(trim(payload->>'code')) or lower(email)=lower(trim(payload->>'email')))) then raise exception 'Staff code or email already exists';end if;
  if nullif(payload->>'email','') is not null and payload->>'email' !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Enter a valid email';end if;
  if sid is null then
   insert into public.payroll_staff(company_id,code,name,email,department,designation,joining_date,biometric_id,probation_end)
   values(cid,nullif(trim(payload->>'code'),''),nullif(trim(payload->>'name'),''),nullif(lower(trim(payload->>'email')),''),coalesce(payload->>'department',''),coalesce(payload->>'designation',''),(payload->>'joining_date')::date,nullif(payload->>'biometric_id',''),nullif(payload->>'probation_end','')::date) returning id into sid;
   insert into public.payroll_profiles(staff_id,company_id) values(sid,cid);
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by)
   values(cid,sid,(payload->>'joining_date')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,uid);
  else
   if nullif(lower(trim(payload->>'email')),'') is distinct from st.email and st.user_id is not null then raise exception 'Linked email changes require account review';end if;
   update public.payroll_staff set email=nullif(lower(trim(payload->>'email')),''),name=nullif(trim(payload->>'name'),''),department=payload->>'department',designation=payload->>'designation',biometric_id=nullif(payload->>'biometric_id',''),probation_end=nullif(payload->>'probation_end','')::date where id=sid;
  end if;
  update public.payroll_profiles set bank_account=coalesce(payload->>'bank_account',''),ifsc=coalesce(payload->>'ifsc',''),pan=coalesce(payload->>'pan',''),uan=coalesce(payload->>'uan',''),esi_number=coalesce(payload->>'esi_number',''),pf_enabled=coalesce((payload->>'pf_enabled')::boolean,false),esi_enabled=coalesce((payload->>'esi_enabled')::boolean,false),deposit_eligible=coalesce((payload->>'deposit_eligible')::boolean,false) where staff_id=sid;
  if nullif(payload->>'manager_email','') is not null then
   select u.id into target_uid from auth.users u join public.payroll_members m on m.user_id=u.id where m.company_id=cid and m.role='manager' and lower(u.email)=lower(payload->>'manager_email');
   if target_uid is null then raise exception 'Assign a confirmed manager role before team mapping';end if;
   update public.payroll_staff set manager_user_id=target_uid where id=sid;
  end if;
  update public.payroll_staff set
   shift_name=coalesce(nullif(trim(payload->>'shift_name'),''),shift_name),
   shift_start=coalesce(nullif(payload->>'shift_start','')::time,shift_start),shift_end=coalesce(nullif(payload->>'shift_end','')::time,shift_end),
   break_minutes=coalesce(nullif(payload->>'break_minutes','')::int,break_minutes),
   late_grace=coalesce(nullif(payload->>'late_grace','')::int,late_grace),early_grace=coalesce(nullif(payload->>'early_grace','')::int,early_grace) where id=sid;
  if payload ? 'personal_details' then
   j=payload->'personal_details';
   if jsonb_typeof(j) is distinct from 'object' or exists(select 1 from jsonb_object_keys(j) k where not (k=ANY(array['S NO','Staff Name','Staff Code','Biometric Code','Staff ERPCode','Staff Department Name','Date Of Birth','Sex','Marital Status','Marriage Anniversary','Email','Alternate Email','Mobile No','Alternate No','Emergency No','Whatsapp No','Father Name','Father Occupation','Father PhoneNo','Spouse Name','Spouse PhoneNo','Spouse Ocupation','Address','Landmark1','Landmark2','Country Name','State Name','City Name','AdhaarCard No','PANCard No','Passport No','Government ID','Caste','Sub Caste','Nationality','CitizenShip','Religion','BloodGroup','Bank Name','Bank AccountNo','EPFNo','UAN','ESINo','Bank BranchName','Bank CityName','Bank StateName','Staff Payroll Entity','IFSCCode','Designation','Specialization','Qualification','CTET Qualified','Trained As','Date Of Joining','Date Of InActive','Employment Status','Previous Experience','Experience','Total Experience','Previous InstitutionName','Previous Designation','Security Deposit','Date','Payment Mode','Remarks','UserType Name','AccessLevel','IsDivorced','MotherName','Employment Category','BED Course','Subjects Assigned','NameAsPerBank']::text[]))) then raise exception 'Invalid personnel fields';end if;
   insert into public.payroll_staff_details(staff_id,company_id,details) values(sid,cid,j) on conflict(staff_id) do update set details=excluded.details;
   update public.payroll_staff set erp_code=coalesce(j->>'Staff ERPCode',''),employment_status=coalesce(j->>'Employment Status',''),employment_category=coalesce(j->>'Employment Category','') where id=sid;
  end if;
  rec=sid;
 elsif action='initial_salary' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if sid is null or exists(select 1 from public.payroll_salaries where staff_id=sid) then raise exception 'Initial salary already exists; use the increment workflow';end if;
  if (payload->>'effective_from')::date<st.joining_date then raise exception 'Salary cannot predate joining';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month>=(date_trunc('month',(payload->>'effective_from')::date))::date and status in ('locked','released','paid')) then raise exception 'Payroll is locked; use a reviewed adjustment';end if;
  insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,uid);
 elsif action='tax_inputs' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  update public.payroll_profiles set annual_tax=(payload->>'annual_tax')::numeric,tax_paid=(payload->>'tax_paid')::numeric,other_deductions=(payload->>'other_deductions')::numeric,pt=(payload->>'pt')::numeric where staff_id=sid;
 elsif action='attendance_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if (payload->>'to_date')::date<(payload->>'from_date')::date or (payload->>'to_date')::date-(payload->>'from_date')::date>31 then raise exception 'Choose at most 32 days';end if;
  for day in select generate_series((payload->>'from_date')::date,(payload->>'to_date')::date,interval '1 day')::date loop
   if day<st.joining_date or day>coalesce(st.leaving_date,'infinity'::date) then raise exception 'Attendance falls outside employment dates';end if;
   if exists(select 1 from public.payroll_late_reviews where staff_id=sid and month=date_trunc('month',day)::date and status='active') then raise exception 'Reopen this staff monthly late review before editing attendance';end if;
   if exists(select 1 from public.payroll_runs where company_id=cid and month=date_trunc('month',day)::date and status in ('locked','released','paid')) then raise exception 'Payroll month is locked; use a reviewed adjustment';end if;
   insert into public.payroll_attendance(company_id,staff_id,work_date,status,in_time,out_time,late_minutes,early_minutes,note,reviewed_by)
   values(cid,sid,day,payload->>'status',nullif(payload->>'in_time','')::time,nullif(payload->>'out_time','')::time,coalesce((payload->>'late_minutes')::int,0),coalesce((payload->>'early_minutes')::int,0),coalesce(payload->>'note',''),uid)
   on conflict(staff_id,work_date) do update set status=excluded.status,in_time=excluded.in_time,out_time=excluded.out_time,late_minutes=excluded.late_minutes,early_minutes=excluded.early_minutes,note=excluded.note,reviewed_by=uid;
   update public.payroll_attendance set raw_late_minutes=coalesce((payload->>'late_minutes')::int,0) where staff_id=sid and work_date=day;
   if coalesce((payload->>'calculate_shift')::boolean,false) then
    if nullif(payload->>'in_time','') is null or nullif(payload->>'out_time','') is null then raise exception 'In and out times are required for shift calculation';end if;
    if (day+((payload->>'out_time')::time)+case when coalesce((payload->>'out_next_day')::boolean,false) then interval '1 day' else interval '0 day' end) <= (day+((payload->>'in_time')::time)) then raise exception 'Out time must be after in time; select next-day out for overnight work';end if;
    update public.payroll_attendance set
     late_minutes=greatest(0,floor(extract(epoch from ((payload->>'in_time')::time-st.shift_start))/60)::int-st.late_grace),
     raw_late_minutes=greatest(0,floor(extract(epoch from ((payload->>'in_time')::time-st.shift_start))/60)::int),
     early_minutes=greatest(0,floor(extract(epoch from ((day+st.shift_end+case when st.shift_end<st.shift_start then interval '1 day' else interval '0 day' end)-(day+(payload->>'out_time')::time+case when coalesce((payload->>'out_next_day')::boolean,false) then interval '1 day' else interval '0 day' end)))/60)::int-st.early_grace),
     shift_snapshot=jsonb_build_object('name',st.shift_name,'start',st.shift_start,'end',st.shift_end,'break_minutes',st.break_minutes,'late_grace',st.late_grace,'early_grace',st.early_grace,'out_next_day',coalesce((payload->>'out_next_day')::boolean,false)) where staff_id=sid and work_date=day;
   else
    update public.payroll_attendance set shift_snapshot=null where staff_id=sid and work_date=day;
   end if;
  end loop;
 elsif action='punch_import' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if jsonb_array_length(payload->'rows')>1000 then raise exception 'Import at most 1,000 punches per batch';end if;
  units=0;
  for j in select * from jsonb_array_elements(payload->'rows') loop
   select id into sid from public.payroll_staff where company_id=cid and biometric_id=j->>'biometric_id' and status='active';
   if sid is null then raise exception 'Unknown biometric ID: %',j->>'biometric_id';end if;
   insert into public.payroll_punches(company_id,staff_id,device_id,event_id,event_time,direction) values(cid,sid,nullif(j->>'device_id',''),nullif(j->>'event_id',''),(j->>'event_timestamp_iso8601')::timestamptz,lower(j->>'punch_direction')) on conflict(company_id,device_id,event_id) do nothing;
   if found then units=units+1;end if;
  end loop;
  out=jsonb_build_object('inserted',units);
 elsif action='leave_apply' then
  if not payroll_private.own(sid) then raise exception 'Apply leave through your own staff login';end if;
  v_email=payroll_private.leave_office(sid);
  if v_email is null then raise exception 'No leave approval policy for this staff group; contact HR';end if;
  select a.user_id into target_uid from public.payroll_leave_approvers a join public.payroll_members m on m.company_id=a.company_id and m.user_id=a.user_id
  where a.company_id=cid and a.office=v_email
  and not exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='separated')
  and (m.role<>'staff' or exists(select 1 from public.payroll_staff s where s.company_id=cid and s.user_id=a.user_id and s.status='active'));
  if target_uid is null then raise exception 'The % approver is not configured or inactive; contact your administrator',v_email;end if;
  if target_uid=uid then raise exception 'Self-approval route is not allowed; ask administrator to correct the approver';end if;
  if length(trim(payload->>'reason'))<3 then raise exception 'Enter a reason';end if;
  if (payload->>'to_date')::date<(payload->>'from_date')::date or (payload->>'to_date')::date-(payload->>'from_date')::date>366 then raise exception 'Invalid leave dates';end if;
  if (payload->>'from_date')::date<st.joining_date or (payload->>'to_date')::date>coalesce(st.leaving_date,'infinity'::date) then raise exception 'Leave falls outside employment';end if;
  if (payload->>'half_day')::boolean and payload->>'from_date'<>payload->>'to_date' then raise exception 'Half-day requests must use one date';end if;
  if exists(select 1 from public.payroll_leaves where staff_id=sid and status in ('submitted','approved') and daterange(from_date,to_date,'[]') && daterange((payload->>'from_date')::date,(payload->>'to_date')::date,'[]')) then raise exception 'Another leave request overlaps these dates';end if;
  select count(*) into units from generate_series((payload->>'from_date')::date,(payload->>'to_date')::date,interval '1 day')d where c.settings->'working_days' @> jsonb_build_array(extract(isodow from d)::int) and not c.settings->'holidays' @> jsonb_build_array(d::date::text);
  if (payload->>'half_day')::boolean then units=units/2;end if;
  if units<=0 then raise exception 'No working leave days in this request';end if;
  select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=payload->>'leave_type';
  if not found then raise exception 'Leave type not found';end if;
  select coalesce(sum(l.units),0) into reserved from public.payroll_leaves l where staff_id=sid and status='submitted' and leave_type=payload->>'leave_type';
  if paid_type and units+reserved>coalesce((st.leave_balances->>(payload->>'leave_type'))::numeric,0) then raise exception 'Insufficient available leave balance';end if;
  insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,half_day,units,reason,created_by,approval_office) values(cid,sid,payload->>'leave_type',(payload->>'from_date')::date,(payload->>'to_date')::date,(payload->>'half_day')::boolean,units,payload->>'reason',uid,v_email) returning id into rec;
 elsif action='leave_decide' then
  select * into le from public.payroll_leaves where id=rec and company_id=cid for update;if not found then raise exception 'Leave request not found';end if;
  select * into st from public.payroll_staff where id=le.staff_id for update;
  if not payroll_private.leave_can_decide(rec) then raise exception 'Only the assigned company approval office can decide this leave';end if;
  if le.created_by=uid then raise exception 'You cannot approve your own leave';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month between date_trunc('month',le.from_date)::date and date_trunc('month',le.to_date)::date and status in ('locked','released','paid')) then raise exception 'Affected payroll is locked; use adjustment process';end if;
  if payload->>'decision'='cancelled' then
   if le.status<>'approved' then raise exception 'Only approved leave can be cancelled here';end if;
   select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=le.leave_type;
   if paid_type then update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[le.leave_type],to_jsonb((leave_balances->>le.leave_type)::numeric+le.units)) where id=le.staff_id;insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,leave_id,event) values(cid,le.staff_id,le.leave_type,le.units,'Approved cancellation',le.id,'cancelled');end if;
  else
   if le.status<>'submitted' or payload->>'decision' not in ('approved','rejected') then raise exception 'Request is no longer pending';end if;
   if payload->>'decision'='approved' then
    select paid into paid_type from public.payroll_leave_policies where company_id=cid and code=le.leave_type;
    if paid_type then
     balance=coalesce((st.leave_balances->>le.leave_type)::numeric,0);if balance<le.units then raise exception 'Insufficient leave balance';end if;
     update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[le.leave_type],to_jsonb(balance-le.units)) where id=le.staff_id;
     insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,leave_id,event) values(cid,le.staff_id,le.leave_type,-le.units,'Approved leave',le.id,'approved');
    end if;
   end if;
  end if;
  update public.payroll_leaves set status=payload->>'decision',reviewed_by=uid where id=rec;
 elsif action='leave_withdraw' then
  update public.payroll_leaves set status='cancelled' where id=rec and company_id=cid and created_by=uid and status='submitted';if not found then raise exception 'Only your pending request can be withdrawn';end if;
 elsif action='leave_credit' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  units=(payload->>'units')::numeric;balance=coalesce((st.leave_balances->>(payload->>'leave_type'))::numeric,0)+units;
  if balance<0 or length(coalesce(payload->>'reason',''))<3 then raise exception 'Invalid balance or reason';end if;
  update public.payroll_staff set leave_balances=jsonb_set(leave_balances,array[payload->>'leave_type'],to_jsonb(balance)) where id=sid;
  insert into public.payroll_leave_ledger(company_id,staff_id,leave_type,units,reason,event) values(cid,sid,payload->>'leave_type',units,payload->>'reason','adjustment');
 elsif action='leave_policy' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  insert into public.payroll_leave_policies(company_id,code,annual_entitlement,paid,description) values(cid,upper(payload->>'code'),(payload->>'annual_entitlement')::numeric,(payload->>'paid')::boolean,payload->>'description') on conflict(company_id,code) do update set annual_entitlement=excluded.annual_entitlement,description=excluded.description;
 elsif action='document_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if length(coalesce(payload->>'body',''))<30 then raise exception 'Letter content is too short';end if;
  insert into public.payroll_documents(company_id,staff_id,type,recipient,body,signatory,created_by,effective_date) values(cid,sid,payload->>'type',payload->>'recipient',payload->>'body',coalesce(payload->>'signatory',''),uid,nullif(payload->>'effective_date','')::date) returning id into rec;
 elsif action='document_decide' then
  select * into doc from public.payroll_documents where id=rec and company_id=cid for update;if not found then raise exception 'Document not found';end if;
  if payload->>'decision'='acknowledged' then
   if not payroll_private.own(doc.staff_id) or doc.status<>'issued' then raise exception 'Only the recipient can acknowledge an issued letter';end if;
  else
   if r<>'admin' then raise exception 'Authorized administrator required';end if;
   if doc.body ~ '\[[^\]]+\]' or trim(doc.signatory)='' then raise exception 'Resolve placeholders and signatory before approval';end if;
   if payload->>'decision'='approved' and doc.status='draft' then null;
   elsif payload->>'decision'='issued' and doc.status='approved' then null;
   else raise exception 'Invalid document transition';end if;
  end if;
  update public.payroll_documents set status=payload->>'decision',approved_by=case when payload->>'decision'='approved' then uid else approved_by end,number=case when payload->>'decision'='issued' then 'HR-'||upper(substr(id::text,1,8)) else number end,issued_at=case when payload->>'decision'='issued' then now() else issued_at end where id=rec;
 elsif action='assessment_save' then
  if r not in ('admin','hr') and not (r='manager' and payroll_private.team(sid)) then raise exception 'Assessment access required';end if;
  if st.user_id=uid then raise exception 'Cannot finalize your own assessment';end if;
  select sum((v->>'weight')::numeric),sum((v->>'weight')::numeric*(v->>'rating')::numeric)/100 into units,score from jsonb_array_elements(payload->'ratings')v;
  if units<>100 or exists(select 1 from jsonb_array_elements(payload->'ratings')v where (v->>'rating')::numeric not between 1 and 5 or (v->>'weight')::numeric<0) then raise exception 'Invalid assessment ratings or weights';end if;
  insert into public.payroll_assessments(company_id,staff_id,period,ratings,score,comments,created_by) values(cid,sid,payload->>'period',payload->'ratings',score,payload->>'comments',uid) returning id into rec;
 elsif action='increment_save' then
  if r not in ('admin','hr') then raise exception 'HR access required';end if;
  if (payload->>'effective_from')::date<st.joining_date then raise exception 'Increment predates employment';end if;
  if exists(select 1 from public.payroll_runs where company_id=cid and month>=(date_trunc('month',(payload->>'effective_from')::date))::date and status in ('locked','released','paid')) then raise exception 'Backdated change affects locked payroll; reviewed arrears workflow is required';end if;
  insert into public.payroll_increments(company_id,staff_id,effective_from,basic,da,hra,other,reason,created_by) values(cid,sid,(payload->>'effective_from')::date,(payload->>'basic')::numeric,(payload->>'da')::numeric,(payload->>'hra')::numeric,(payload->>'other')::numeric,payload->>'reason',uid) returning id into rec;
 elsif action='increment_decide' then
  select * into inc from public.payroll_increments where id=rec and company_id=cid for update;if not found then raise exception 'Increment not found';end if;
  if payload->>'decision'='accountant_reviewed' and inc.status='recommended' and r in ('admin','accountant') and inc.created_by<>uid then update public.payroll_increments set status='accountant_reviewed',reviewed_by=uid where id=rec;
  elsif payload->>'decision'='approved' and inc.status='accountant_reviewed' and r='admin' then
   if exists(select 1 from public.payroll_runs where company_id=cid and month>=date_trunc('month',inc.effective_from)::date and status in ('locked','released','paid')) then raise exception 'Payroll was locked after recommendation; use reviewed arrears';end if;
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic,da,hra,other,approved_by) values(cid,inc.staff_id,inc.effective_from,inc.basic,inc.da,inc.hra,inc.other,uid);
   update public.payroll_increments set status='approved',approved_by=uid where id=rec;
  elsif payload->>'decision'='rejected' and inc.status in ('recommended','accountant_reviewed') and r='admin' then update public.payroll_increments set status='rejected' where id=rec;
  else raise exception 'Requires independent accountant review followed by administrator approval';end if;
 elsif action='service_change' then
  if r<>'admin' then raise exception 'Authorized administrator required';end if;
  if payload->>'service_status' not in ('probation','confirmed','extended') then raise exception 'Invalid service status';end if;
  update public.payroll_staff set service_status=payload->>'service_status',probation_end=nullif(payload->>'probation_end','')::date where id=sid;
 elsif action='separate' then
  if r<>'admin' or payload->>'confirm'<>'SEPARATE' then raise exception 'Explicit administrator separation decision required';end if;
  if st.user_id=uid then raise exception 'Cannot separate your own account';end if;
  if (payload->>'leaving_date')::date>current_date then raise exception 'Future exits must be executed on the effective date';end if;
  if length(coalesce(payload->>'reason',''))<5 then raise exception 'Record the authorized decision reason';end if;
  update public.payroll_staff set status='separated',leaving_date=(payload->>'leaving_date')::date where id=sid;
 elsif action='deposit_refund' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  select coalesce(sum(amount),0) into balance from public.payroll_deposits where staff_id=sid;
  units=(payload->>'amount')::numeric;if units<=0 or units>balance or length(coalesce(payload->>'reason',''))<5 then raise exception 'Invalid refund amount or payment reference';end if;
  insert into public.payroll_deposits(company_id,staff_id,amount,reason,created_by) values(cid,sid,-units,payload->>'reason',uid);
 elsif action='payroll_calculate' then
  if r not in ('admin','accountant') then raise exception 'Accountant access required';end if;
  rec=payroll_private.calculate(cid,(payload->>'month')::date);
 elsif action='payroll_decide' then
  select * into run from public.payroll_runs where id=rec and company_id=cid for update;if not found then raise exception 'Payroll not found';end if;
  if payload->>'decision' in ('hr_reviewed','accountant_reviewed','locked') then
   if run.input_hash<>payroll_private.fingerprint(cid) then raise exception 'Inputs changed; recalculate payroll before review';end if;
   if exists(select 1 from public.payroll_lines where run_id=rec and jsonb_array_length(issues)>0) then raise exception 'Resolve payroll exceptions before approval';end if;
  end if;
  if payload->>'decision'='hr_reviewed' and run.status='calculated' and r in ('admin','hr') then update public.payroll_runs set status='hr_reviewed',hr_by=uid where id=rec;
  elsif payload->>'decision'='accountant_reviewed' and run.status='hr_reviewed' and r in ('admin','accountant') and run.created_by<>uid then update public.payroll_runs set status='accountant_reviewed',accountant_by=uid where id=rec;
  elsif payload->>'decision'='locked' and run.status='accountant_reviewed' and r='admin' then
   update public.payroll_runs set status='locked',authorized_by=uid where id=rec;
   insert into public.payroll_deposits(company_id,staff_id,amount,reason,line_id,created_by) select cid,staff_id,(deductions->>'Security deposit')::numeric,'Payroll '||run.month,id,uid from public.payroll_lines where run_id=rec and (deductions->>'Security deposit')::numeric>0;
  elsif payload->>'decision'='released' and run.status='locked' and r='admin' then update public.payroll_runs set status='released' where id=rec;
  elsif payload->>'decision'='paid' and run.status='released' and r in ('admin','accountant') and length(coalesce(payload->>'payment_reference',''))>=5 then
   update public.payroll_lines set payment_reference=payload->>'payment_reference' where run_id=rec;update public.payroll_runs set status='paid' where id=rec;
  else raise exception 'Invalid transition; independent review or payment evidence may be missing';end if;
 else raise exception 'Unknown payroll action';end if;
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,action,coalesce(rec,sid)::text);
 out=coalesce(out,jsonb_build_object('id',coalesce(rec,sid),'ok',true));
 if reqid is not null then insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(reqid,cid,uid,action,md5(payload::text),out);end if;
 return out;
end$$;

revoke all on all functions in schema payroll_private from public,anon,authenticated;
grant execute on function payroll_private.role(uuid),payroll_private.own(uuid),payroll_private.team(uuid),payroll_private.leave_can_decide(uuid),payroll_private.late_can_review(uuid),payroll_private.dispatch(text,jsonb) to authenticated;
create function public.payroll_api(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select payroll_private.dispatch(action,payload)$$;
revoke all on function public.payroll_api(text,jsonb) from public,anon;
grant execute on function public.payroll_api(text,jsonb) to authenticated;

-- Provision the first administrator separately using docs/operations.md.

create index payroll_staff_user_idx on public.payroll_staff(user_id);
create index payroll_staff_manager_idx on public.payroll_staff(manager_user_id);
create index payroll_leaves_staff_idx on public.payroll_leaves(staff_id,status);
create index payroll_punches_company_time_idx on public.payroll_punches(company_id,event_time desc);
create index payroll_documents_staff_idx on public.payroll_documents(staff_id,status);
create index payroll_lines_company_idx on public.payroll_lines(company_id,run_id);
notify pgrst,'reload schema';
