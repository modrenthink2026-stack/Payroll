-- Temporary payment holds leave payroll earnings, deductions and staff service unchanged.
create table payroll_private.salary_payment_holds(
 company_id uuid not null,staff_id uuid not null,month date not null,
 status text not null check(status in ('held','released')),revision integer not null check(revision>0),
 reason text not null check(length(trim(reason)) between 5 and 1000),updated_by uuid not null references auth.users,updated_at timestamptz not null default now(),
 primary key(company_id,staff_id,month),foreign key(company_id,staff_id) references public.payroll_staff(company_id,id),
 check(month=date_trunc('month',month)::date)
);
create table payroll_private.salary_payment_hold_events(
 id bigint generated always as identity primary key,company_id uuid not null,staff_id uuid not null,month date not null,
 revision integer not null,status text not null,reason text not null,actor uuid not null references auth.users,created_at timestamptz not null default now(),
 foreign key(company_id,staff_id,month) references payroll_private.salary_payment_holds(company_id,staff_id,month),unique(company_id,staff_id,month,revision)
);
alter table payroll_private.salary_payment_holds enable row level security;
alter table payroll_private.salary_payment_hold_events enable row level security;
revoke all on payroll_private.salary_payment_holds,payroll_private.salary_payment_hold_events from public,anon,authenticated;

create function payroll_private.payment_dispatch(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid=nullif(payload->>'company_id','')::uuid;uid uuid=auth.uid();sid uuid=nullif(payload->>'staff_id','')::uuid;
 rid uuid=nullif(payload->>'id','')::uuid;r text;m date;out jsonb;req uuid=nullif(payload->>'request_id','')::uuid;
 h payroll_private.salary_payment_holds;run public.payroll_runs;ln public.payroll_lines;previous_revision integer;changed integer;
begin
 if action='state' then
  out=payroll_private.dispatch(action,payload);r=payroll_private.role(cid);
  if r in ('admin','accountant','hr') then
   out=out||jsonb_build_object('salary_holds',coalesce((select jsonb_agg(t order by month desc,staff_id) from payroll_private.salary_payment_holds t where company_id=cid),'[]'::jsonb));
  end if;return out;
 end if;
 if action not in ('salary_hold_set','salary_payment_state','salary_hold_history') and not(action='payroll_decide' and payload->>'decision'='paid') then return payroll_private.dispatch(action,payload);end if;
 if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'Confirmed authentication required';end if;
 r=payroll_private.role(cid);if r is null or r not in ('admin','accountant','hr') then raise exception 'Authorized company access required';end if;
 if r='hr' and (action='salary_payment_state' or action='payroll_decide') then raise exception 'Accounts access required';end if;
 -- Same company lock order as payroll calculation, approvals and other writes.
 perform 1 from public.payroll_companies where id=cid for update;
 if action='salary_hold_history' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Choose a calendar month';end if;
  return coalesce((select jsonb_agg(e order by id desc) from payroll_private.salary_payment_hold_events e where company_id=cid and month=m),'[]'::jsonb);
 end if;
 if action='salary_payment_state' then
  select * into run from public.payroll_runs where id=rid and company_id=cid;if not found then raise exception 'Payroll not found';end if;
  return jsonb_build_object('held_count',(select count(*) from public.payroll_lines l join payroll_private.salary_payment_holds ph on ph.company_id=l.company_id and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held' where l.run_id=rid),
   'paid_count',(select count(*) from public.payroll_lines where run_id=rid and payment_reference is not null),
   'rows',coalesce((select jsonb_agg(jsonb_build_object('staff_id',l.staff_id,'name',s.name,'bank_account',p.bank_account,'ifsc',p.ifsc,'net',l.net) order by s.code,l.staff_id) from public.payroll_lines l join public.payroll_staff s on s.id=l.staff_id left join public.payroll_profiles p on p.staff_id=l.staff_id where l.run_id=rid and l.payment_reference is null and not exists(select 1 from payroll_private.salary_payment_holds ph where ph.company_id=cid and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held')),'[]'::jsonb));
 end if;
 if action='salary_hold_set' and (r not in ('admin','hr','accountant') or (r<>'admin' and payload->>'status' is distinct from 'held')) then raise exception 'HR or Accountant may hold payment; only Administrator, Principal or President may release';end if;
 if req is null then raise exception 'Request ID required';end if;
 select response into out from payroll_private.requests where token=req and company_id=cid and user_id=uid and operation=action and request_hash=md5(payload::text);
 if found then return out;end if;
 if exists(select 1 from payroll_private.requests where token=req) then raise exception 'Request ID reused with different data';end if;
 if action='salary_hold_set' then
  m=(payload->>'month')::date;if m is null or m<>date_trunc('month',m)::date then raise exception 'Choose a calendar month';end if;
  if coalesce(payload->>'status','') not in ('held','released') or length(trim(coalesce(payload->>'reason',''))) not between 5 and 1000 then raise exception 'Choose hold or release and enter a reason (5–1000 characters)';end if;
  if not exists(select 1 from public.payroll_staff where id=sid and company_id=cid) then raise exception 'Staff not found in this company';end if;
  select * into run from public.payroll_runs where company_id=cid and month=m for update;
  select * into ln from public.payroll_lines where run_id=run.id and staff_id=sid and company_id=cid for update;
  if run.status='paid' or ln.payment_reference is not null then raise exception 'Payment is already reconciled; a hold cannot change a paid salary';end if;
  select * into h from payroll_private.salary_payment_holds where company_id=cid and staff_id=sid and month=m for update;
  previous_revision=coalesce(h.revision,0);
  if nullif(payload->>'expected_revision','')::integer is distinct from previous_revision then raise exception 'Hold changed; reload before saving';end if;
  if h.status is not distinct from payload->>'status' or (payload->>'status'='released' and h.status is distinct from 'held') then raise exception 'Hold state changed; reload before saving';end if;
  insert into payroll_private.salary_payment_holds(company_id,staff_id,month,status,revision,reason,updated_by) values(cid,sid,m,payload->>'status',previous_revision+1,trim(payload->>'reason'),uid)
   on conflict(company_id,staff_id,month) do update set status=excluded.status,revision=excluded.revision,reason=excluded.reason,updated_by=uid,updated_at=now() returning * into h;
  insert into payroll_private.salary_payment_hold_events(company_id,staff_id,month,revision,status,reason,actor) values(cid,sid,m,h.revision,h.status,h.reason,uid);
  out=to_jsonb(h);
 else
  select * into run from public.payroll_runs where id=rid and company_id=cid for update;if not found then raise exception 'Payroll not found';end if;
  if run.status<>'released' or length(trim(coalesce(payload->>'payment_reference','')))<5 then raise exception 'Release payslips first and provide reconciled payment evidence';end if;
  update public.payroll_lines l set payment_reference=trim(payload->>'payment_reference') where l.run_id=rid and l.payment_reference is null and not exists(select 1 from payroll_private.salary_payment_holds ph where ph.company_id=cid and ph.staff_id=l.staff_id and ph.month=run.month and ph.status='held');
  get diagnostics changed=row_count;
  if changed=0 then raise exception 'No unpaid, unheld salaries to reconcile';end if;
  if not exists(select 1 from public.payroll_lines where run_id=rid and payment_reference is null) then update public.payroll_runs set status='paid' where id=rid;end if;
  out=jsonb_build_object('id',rid,'ok',true,'reconciled_staff',changed,'remaining_unpaid',(select count(*) from public.payroll_lines where run_id=rid and payment_reference is null));
 end if;
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,uid,action,coalesce(sid,rid)::text);
 insert into payroll_private.requests(token,company_id,user_id,operation,request_hash,response) values(req,cid,uid,action,md5(payload::text),out);
 return out;
end$$;
revoke all on function payroll_private.payment_dispatch(text,jsonb) from public,anon;
grant execute on function payroll_private.payment_dispatch(text,jsonb) to authenticated;
create or replace function public.payroll_api(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select payroll_private.payment_dispatch(action,payload)$$;
