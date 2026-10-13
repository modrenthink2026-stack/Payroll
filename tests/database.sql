-- Business and permission checks against PostgreSQL. All test records roll back.
-- This simulates verified identities inside a transaction; it is not a password-login test.
begin;
do $$
declare owner_id uuid; reviewer uuid=gen_random_uuid(); worker uuid=gen_random_uuid(); cid uuid; othercid uuid; sid uuid; rid uuid; lid uuid; did uuid; inc uuid; j jsonb; amount numeric; caught boolean; req uuid=gen_random_uuid();
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(reviewer,'qa-reviewer@example.invalid',now()),(worker,'qa-worker@example.invalid',now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA transaction only"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"QA second tenant"}')->>'id')::uuid;
 insert into public.payroll_members values(cid,reviewer,'accountant');
 sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','QA001','name','QA Worker','email','qa-worker@example.invalid','joining_date','2026-10-01','basic',20000,'da',2000,'hra',5000,'other',3000,'pf_enabled',true,'esi_enabled',true,'deposit_eligible',true))->>'id')::uuid;
 update public.payroll_companies set settings=settings||'{"statutory_reviewed":true,"deposit_enabled":true,"deposit_cap":10000,"deposit_policy":"QA reviewed test policy"}' where id=cid;
 -- A missing day is an exception, never automatically unpaid.
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and jsonb_array_length(issues)>0 and lop=0) then raise exception 'Missing-attendance safeguard failed';end if;
 perform public.payroll_api('attendance_save',jsonb_build_object('company_id',cid,'staff_id',sid,'from_date','2026-10-01','to_date','2026-10-31','status','present'));
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_lines where run_id=rid and gross=30000 and (deductions->>'PF')::numeric=2640 and (deductions->>'ESI')::numeric=165 and (deductions->>'Security deposit')::numeric=3000 and net=24195 and jsonb_array_length(issues)=0) then raise exception 'Independent full-month arithmetic failed';end if;
 -- Reviewer must differ from preparer.
 perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','hr_reviewed'));
 caught=false;begin perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','accountant_reviewed'));exception when others then caught=true;end;
 if not caught then raise exception 'Self-review was permitted';end if;
 -- Input changes invalidate approval.
 perform public.payroll_api('tax_inputs',jsonb_build_object('company_id',cid,'staff_id',sid,'annual_tax',7000,'tax_paid',0,'other_deductions',0,'pt',0));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','accountant_reviewed'));exception when others then caught=true;end;
 if not caught then raise exception 'Stale payroll review permitted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 rid=(public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'))->>'id')::uuid;
 perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','hr_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reviewer,'role','authenticated')::text,true);
 perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','accountant_reviewed'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','locked'));
 select sum(d.amount) into amount from public.payroll_deposits d where staff_id=sid;
 if amount<>3000 then raise exception 'Deposit lock posting mismatch';end if;
 caught=false;begin perform public.payroll_api('payroll_calculate',jsonb_build_object('company_id',cid,'month','2026-10-01'));exception when others then caught=true;end;
 if not caught then raise exception 'Locked payroll recalculated';end if;
 perform public.payroll_api('payroll_decide',jsonb_build_object('company_id',cid,'id',rid,'decision','released'));
 -- Deduplicate request retries and prevent the same refund reference being posted twice.
 j=jsonb_build_object('company_id',cid,'staff_id',sid,'amount',500,'reason','BANK-QA-REFUND-1','request_id',req);
 perform public.payroll_api('deposit_refund',j);perform public.payroll_api('deposit_refund',j);
 if (select sum(d.amount) from public.payroll_deposits d where staff_id=sid)<>2500 then raise exception 'Refund retry duplicated';end if;
 caught=false;begin perform public.payroll_api('deposit_refund',j||jsonb_build_object('request_id',gen_random_uuid()));exception when others then caught=true;end;
 if not caught then raise exception 'Duplicate payment reference permitted';end if;
 -- Draft letters do not alter service; unresolved placeholders block approval.
 did=(public.payroll_api('document_save',jsonb_build_object('company_id',cid,'staff_id',sid,'type','Service confirmation','recipient','QA Worker','body','Reviewed draft confirms service on [Date] only after approval.','signatory','QA Signatory'))->>'id')::uuid;
 if (select service_status from public.payroll_staff where id=sid)<>'probation' then raise exception 'Draft changed service';end if;
 caught=false;begin perform public.payroll_api('document_decide',jsonb_build_object('company_id',cid,'id',did,'decision','approved'));exception when others then caught=true;end;
 if not caught then raise exception 'Placeholder letter approved';end if;
 -- Verified staff email links correctly and cannot read another tenant or salary.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 perform public.payroll_api('bootstrap','{}');
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if jsonb_array_length(j->'staff')<>1 or jsonb_array_length(j->'documents')<>0 or jsonb_array_length(j->'lines')<>1 then raise exception 'Staff visibility mismatch';end if;
 caught=false;begin perform public.payroll_api('state',jsonb_build_object('company_id',othercid));exception when others then caught=true;end;
 if not caught then raise exception 'Cross-company access permitted';end if;
 caught=false;begin perform public.payroll_api('tax_inputs',jsonb_build_object('company_id',cid,'staff_id',sid,'annual_tax',0,'tax_paid',0,'other_deductions',0,'pt',0));exception when others then caught=true;end;
 if not caught then raise exception 'Staff edited tax inputs';end if;
 -- Leave reservations and approval/cancellation affect the balance once.
 lid=(public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','CL','from_date','2026-11-02','to_date','2026-11-02','half_day',false,'reason','QA leave'))->>'id')::uuid;
 caught=false;begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','CL','from_date','2026-11-02','to_date','2026-11-02','half_day',false,'reason','Overlap'));exception when others then caught=true;end;
 if not caught then raise exception 'Overlapping leave accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',lid,'decision','approved'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>11 then raise exception 'Leave debit mismatch';end if;
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',lid,'decision','cancelled'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>12 then raise exception 'Leave cancellation mismatch';end if;
 -- Direct table RLS is enforced even without using the RPC gateway.
 perform public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','QA002','name','Second Staff','email','other-qa@example.invalid','joining_date','2026-11-01','basic',10000,'da',0,'hra',0,'other',0));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 if (select count(*) from public.payroll_staff where company_id=cid)<>1 then raise exception 'Direct RLS staff isolation failed';end if;
 if exists(select 1 from public.payroll_companies where id=othercid) then raise exception 'Direct RLS company isolation failed';end if;
 if (select count(*) from public.payroll_profiles where company_id=cid)<>1 then raise exception 'Direct RLS salary-profile isolation failed';end if;
 caught=false;begin update public.payroll_profiles set annual_tax=0 where staff_id=sid;exception when insufficient_privilege then caught=true;end;
 if not caught then raise exception 'Direct write privileges escaped RPC';end if;
 execute 'reset role';
 raise notice 'PASS: payroll arithmetic, review separation, stale inputs, locking, deposit/refund retries, placeholder letters, tenant permissions and leave ledger';
end$$;
rollback;
