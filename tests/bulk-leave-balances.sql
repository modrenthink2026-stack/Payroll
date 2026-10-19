-- Rollback-only synthetic leave balance entry scenarios.
begin;
do $$
declare owner_id uuid; cid uuid; othercid uuid; hr_id uuid=gen_random_uuid(); sid uuid; sid2 uuid; outsider uuid; token uuid=gen_random_uuid(); p jsonb; j jsonb; result jsonb; caught boolean; n int;
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Bulk leave QA rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"Bulk leave other tenant rollback"}')->>'id')::uuid;
 insert into auth.users(id,email,email_confirmed_at) values(hr_id,'qa-bulk-leave-hr@example.invalid',now());insert into public.payroll_members values(cid,hr_id,'hr');
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date) values(cid,'BULK-1','Synthetic one',null,'Teaching','2026-10-01') returning id into sid;
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date) values(cid,'BULK-2','Synthetic two',null,'Teaching','2026-10-01') returning id into sid2;
 insert into public.payroll_staff(company_id,code,name,email,department,joining_date) values(othercid,'BULK-X','Synthetic other',null,'Teaching','2026-10-01') returning id into outsider;
 insert into public.payroll_leave_policies(company_id,code,name,annual_entitlement,paid) values(cid,'PL','Custom paid leave',0,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 p=jsonb_build_object('company_id',cid,'department','Teaching','reason','Opening balance October QA','request_id',token,'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"CL":8,"EL":5,"SL":4}'::jsonb,'expected_balances','{"CL":12,"EL":0,"SL":12}'::jsonb),jsonb_build_object('staff_id',sid2,'balances','{"CL":0}'::jsonb,'expected_balances','{"CL":12}'::jsonb)));
 result=public.payroll_bulk_leave_balances(p);
 if (result->>'changed_balances')::int<>4 or (select leave_balances from public.payroll_staff where id=sid)<>'{"CL":8,"EL":5,"SL":4}'::jsonb or (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid2)<>0 then raise exception 'Target balances failed';end if;
 if (select count(*) from public.payroll_leave_ledger where company_id=cid and event='bulk_balance')<>4 or (select sum(units) from public.payroll_leave_ledger where company_id=cid and staff_id=sid)<>-7 then raise exception 'Delta ledger failed';end if;
 perform public.payroll_bulk_leave_balances(p);
 if (select count(*) from public.payroll_leave_ledger where company_id=cid)<>4 then raise exception 'Replay duplicated opening entries';end if;
 -- Stale snapshots, replay-token mismatches, wrong department and cross-company staff are rejected.
 for j in select * from jsonb_array_elements(jsonb_build_array(
 jsonb_build_object('request_id',gen_random_uuid()),
 jsonb_build_object('reason','Changed payload same token'),
 jsonb_build_object('request_id',gen_random_uuid(),'department','Support'),
 jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',outsider,'balances','{"CL":3}'::jsonb,'expected_balances','{"CL":12}'::jsonb))),
 jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"LWP":3}'::jsonb,'expected_balances','{"LWP":0}'::jsonb))),
 jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"UNKNOWN":3}'::jsonb,'expected_balances','{"UNKNOWN":0}'::jsonb))),
 jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"CL":0.25}'::jsonb,'expected_balances','{"CL":8}'::jsonb))),
 jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{}'::jsonb,'expected_balances','{}'::jsonb)))
 )) loop
  caught=false;begin perform public.payroll_bulk_leave_balances(p||j);exception when others then caught=true;end;if not caught then raise exception 'Invalid bulk request accepted: %',j;end if;
 end loop;
 -- Fail on a later staff row: earlier changes and ledger inserts must roll back together.
 caught=false;begin perform public.payroll_bulk_leave_balances(p||jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"CL":6}'::jsonb,'expected_balances','{"CL":8}'::jsonb),jsonb_build_object('staff_id',sid2,'balances','{"CL":-1}'::jsonb,'expected_balances','{"CL":0}'::jsonb))));exception when others then caught=true;end;
 if not caught or (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=sid)<>8 or (select count(*) from public.payroll_leave_ledger where company_id=cid)<>4 then raise exception 'Bulk entry was not atomic';end if;
 insert into public.payroll_leaves(company_id,staff_id,leave_type,from_date,to_date,units,reason,created_by,approval_office) values(cid,sid,'PL','2026-11-02','2026-11-03',2,'Synthetic reservation',owner_id,'principal');
 caught=false;begin perform public.payroll_bulk_leave_balances(p||jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"PL":1}'::jsonb,'expected_balances','{"PL":0}'::jsonb))));exception when others then caught=true;end;if not caught then raise exception 'Pending leave reservation removed';end if;
 perform public.payroll_bulk_leave_balances(p||jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"PL":3.5}'::jsonb,'expected_balances','{"PL":0}'::jsonb))));
 if (select (leave_balances->>'SL')::numeric from public.payroll_staff where id=sid)<>4 then raise exception 'Omitted leave balance changed';end if;
 select count(*) into n from public.payroll_leave_ledger where company_id=cid;
 perform public.payroll_bulk_leave_balances(p||jsonb_build_object('request_id',gen_random_uuid(),'rows',jsonb_build_array(jsonb_build_object('staff_id',sid,'balances','{"CL":8}'::jsonb,'expected_balances','{"CL":8}'::jsonb))));
 if (select count(*) from public.payroll_leave_ledger where company_id=cid)<>n then raise exception 'Unchanged value posted a ledger entry';end if;
 -- Permissions are checked before returning an idempotent response.
 update public.payroll_members set role='staff' where company_id=cid and user_id=hr_id;
 caught=false;begin perform public.payroll_bulk_leave_balances(p);exception when others then caught=true;end;if not caught then raise exception 'Staff or revoked HR reused bulk endpoint';end if;
 update public.payroll_members set role='accountant' where company_id=cid and user_id=hr_id;
 caught=false;begin perform public.payroll_bulk_leave_balances(p);exception when others then caught=true;end;if not caught then raise exception 'Accountant edited leave balance';end if;
 update public.payroll_members set role='hr' where company_id=cid and user_id=hr_id;
 update auth.users set raw_app_meta_data='{"payroll_password_change_required":true}' where id=hr_id;
 caught=false;begin perform public.payroll_bulk_leave_balances(p);exception when others then caught=true;end;if not caught then raise exception 'Temporary password bypass';end if;
end$$;
rollback;
select 'PASS: bulk CL/EL/SL/custom opening targets, delta ledger, explicit zero, omitted cells, pending reservations, stale edits, atomic rollback, idempotency, role and tenant isolation, password-change gate' as result;
