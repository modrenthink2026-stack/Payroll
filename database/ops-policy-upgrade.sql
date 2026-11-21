-- Additive owner-only Ops policy. No company records, users or release grants are changed.
create table payroll_private.ops_policies(
 company_id uuid primary key references public.payroll_companies(id),
 pass_expires_on date, integrations jsonb not null default '{}',
 revision integer not null default 0,updated_by uuid,updated_at timestamptz not null default now()
);
alter table payroll_private.ops_policies enable row level security;
revoke all on payroll_private.ops_policies from public,anon,authenticated;
create function payroll_private.ops_pass_valid(cid uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select not exists(select 1 from payroll_private.ops_policies where company_id=cid and pass_expires_on<(now() at time zone 'Asia/Kolkata')::date)
$$;
revoke all on function payroll_private.ops_pass_valid(uuid) from public,anon;
grant execute on function payroll_private.ops_pass_valid(uuid) to authenticated;
create function public.payroll_ops_policy(payload jsonb) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare cid uuid=nullif(payload->>'company_id','')::uuid; p payroll_private.ops_policies; flags jsonb=coalesce(payload->'integrations','{}');expiry date=nullif(payload->>'pass_expires_on','')::date;
begin
 if auth.uid() is null or not payroll_private.platform_admin() then raise exception 'Platform owner access required' using errcode='42501';end if;
 if payload->>'action'='snapshot' then return jsonb_build_object('policies',coalesce((select jsonb_agg(to_jsonb(x)) from payroll_private.ops_policies x),'[]'));end if;
 if payload->>'action'<>'save' or cid is null then raise exception 'Choose a company policy';end if;
 if jsonb_typeof(flags)<>'object' or exists(select 1 from jsonb_each(flags) x where x.key not in ('whatsapp','payments','bank','gst','ai') or jsonb_typeof(x.value)<>'boolean') then raise exception 'Invalid integration eligibility';end if;
 insert into payroll_private.ops_policies(company_id) values(cid) on conflict do nothing;
 select * into p from payroll_private.ops_policies where company_id=cid for update;
 if (payload->>'revision')::integer is distinct from p.revision then raise exception 'Company policy changed. Reload before saving.' using errcode='40001';end if;
 update payroll_private.ops_policies set pass_expires_on=expiry,integrations=flags,revision=revision+1,updated_by=auth.uid(),updated_at=now() where company_id=cid;
 insert into public.payroll_audit(company_id,actor,action,record_id) values(cid,auth.uid(),'platform_ops_policy',cid::text);
 return jsonb_build_object('ok',true,'revision',p.revision+1);
end $$;
revoke all on function public.payroll_ops_policy(jsonb) from public,anon;
grant execute on function public.payroll_ops_policy(jsonb) to authenticated;
-- Preserve the installed versioned feature gate and add expiry to every feature path.
do $$ declare definition text;begin
 if to_regprocedure('payroll_private.feature_enabled(uuid,text)') is not null then
  definition=pg_get_functiondef('payroll_private.feature_enabled(uuid,text)'::regprocedure);
  if position('ops_pass_valid' in definition)=0 then
   if position('select coalesce((select ' in definition)=0 then raise exception 'Unrecognized feature gate; no changes applied';end if;
   execute replace(definition,'select coalesce((select ','select payroll_private.ops_pass_valid(cid) and coalesce((select ');
  end if;
 else
  definition=pg_get_functiondef('payroll_private.module_enabled(uuid,text)'::regprocedure);
  if position('select exists(' in definition)=0 then raise exception 'Unrecognized module gate';end if;
  execute replace(definition,'select exists(','select payroll_private.ops_pass_valid(cid) and exists(');
 end if;
 -- Older clients must not erase hidden add-on assignments while switching core modules.
 definition=pg_get_functiondef('payroll_private.platform_admin_api(jsonb)'::regprocedure);
 if position('enabled_modules=next_modules' in definition)=0 then raise exception 'Unrecognized platform module updater';end if;
 execute replace(definition,'enabled_modules=next_modules','enabled_modules=company.enabled_modules||next_modules');
end $$;
