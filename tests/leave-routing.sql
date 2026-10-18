-- Synthetic identities and companies only; all data rolls back. No real employee decisions.
begin;
do $$
declare owner_id uuid; cid uuid; othercid uuid; u uuid; sid uuid; lid uuid; j jsonb; caught boolean;
 principals uuid[]=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
 offices text[]=array['principal','director','president','hr'];
 titles text[]=array['Teacher','Staff','Principal','Director','Substaff','Aayah','Attender','Security'];
 expected text[]=array['principal','principal','director','president','hr','hr','hr','hr'];
 workers uuid[]='{}'; staffids uuid[]='{}'; leaves uuid[]='{}'; i int; k int; replacement uuid=gen_random_uuid();
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA leave routing rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"QA leave other company rollback"}')->>'id')::uuid;
 for i in 1..4 loop
  u=principals[i];insert into auth.users(id,email,email_confirmed_at) values(u,'qa-office-'||i||'@example.invalid',now());
  insert into public.payroll_staff(company_id,code,name,email,joining_date,user_id,designation) values(cid,'OFFICE-'||i,'Synthetic officer',null,'2026-10-01',u,initcap(offices[i]));
  insert into public.payroll_members values(cid,u,case when i=4 then 'hr' else 'staff' end);
  perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office',offices[i],'email','qa-office-'||i||'@example.invalid'));
 end loop;
 -- Cross-company and missing account assignments cannot create access.
 caught=false;begin perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',othercid,'office','principal','email','qa-office-1@example.invalid'));exception when others then caught=true;end;
 if not caught then raise exception 'Cross-company approver assignment permitted';end if;
 for i in 1..8 loop
  u=gen_random_uuid();workers=array_append(workers,u);insert into auth.users(id,email,email_confirmed_at) values(u,'qa-leave-worker-'||i||'@example.invalid',now());
  insert into public.payroll_staff(company_id,code,name,email,joining_date,user_id,designation,leave_balances) values(cid,'WORKER-'||i,'Synthetic worker '||i,null,'2026-10-01',u,titles[i],'{"CL":5}') returning id into sid;
  staffids=array_append(staffids,sid);insert into public.payroll_members values(cid,u,'staff');
  if i=1 then
   insert into public.payroll_profiles(company_id,staff_id,bank_account) values(cid,sid,'SYNTHETIC-PRIVATE');
   insert into public.payroll_salaries(company_id,staff_id,effective_from,basic) values(cid,sid,'2026-10-01',12345);
   insert into public.payroll_staff_details(company_id,staff_id,details) values(cid,sid,'{"Address":"Synthetic private address"}');
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  lid=(public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','CL','from_date','2026-11-02','to_date','2026-11-02','half_day',false,'reason','Synthetic QA request'))->>'id')::uuid;
  leaves=array_append(leaves,lid);
  if (select approval_office from public.payroll_leaves where id=lid)<>expected[i] then raise exception 'Wrong approval route for %',titles[i];end if;
  if payroll_private.leave_can_decide(lid) then raise exception 'Applicant allowed self-approval';end if;
  caught=false;begin perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email','qa-leave-worker-1@example.invalid'));exception when others then caught=true;end;
  if not caught then raise exception 'Staff changed approval office';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  caught=false;begin perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',lid,'decision','approved'));exception when others then caught=true;end;
  if not caught then raise exception 'Unassigned administrator override permitted';end if;
 end loop;
 -- Wrong HR route is denied, even though HR can inspect all leave for administration.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',principals[4],'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[1],'decision','approved'));exception when others then caught=true;end;
 if not caught then raise exception 'HR approved teacher leave';end if;
 -- Principal sees only assigned leave plus own staff data, never other staff pay or details.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',principals[1],'role','authenticated')::text,true);
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if jsonb_array_length(j->'leaves')<>2 or jsonb_array_length(j->'staff')<>1 or jsonb_array_length(j->'profiles')<>0 or jsonb_array_length(j->'salaries')<>0 or jsonb_array_length(j->'staff_details')<>0 then raise exception 'Approver visibility expanded beyond leave';end if;
 execute 'set local role authenticated';
 if (select count(*) from public.payroll_leaves where company_id=cid)<>2 then raise exception 'Direct leave RLS mismatch';end if;
 if exists(select 1 from public.payroll_leave_approvers where company_id=cid) then raise exception 'Approval account mapping leaked';end if;
 execute 'reset role';
 -- Approved cancellation restores balance once; rejected leave does not debit.
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[1],'decision','approved'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=staffids[1])<>4 then raise exception 'Debit mismatch';end if;
 caught=false;begin perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[1],'decision','approved'));exception when others then caught=true;end;
 if not caught then raise exception 'Double approval permitted';end if;
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[1],'decision','cancelled'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=staffids[1])<>5 then raise exception 'Cancellation mismatch';end if;
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[2],'decision','rejected'));
 if (select (leave_balances->>'CL')::numeric from public.payroll_staff where id=staffids[2])<>5 then raise exception 'Rejection debited balance';end if;
 -- Every higher/support route approves successfully.
 for i in 3..8 loop
  k=array_position(offices,expected[i]);perform set_config('request.jwt.claims',jsonb_build_object('sub',principals[k],'role','authenticated')::text,true);
  perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[i],'decision','approved'));
 end loop;
 -- Employment group changes do not silently reroute an existing request.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_group_set',jsonb_build_object('company_id',cid,'staff_id',staffids[3],'leave_group','support'));
 if (select approval_office from public.payroll_leaves where id=leaves[3])<>'director' or payroll_private.leave_office(staffids[3])<>'hr' then raise exception 'Route snapshot not retained';end if;
 -- Payroll locks still forbid cancellation, including a correctly assigned approver.
 insert into public.payroll_runs(company_id,month,status,input_hash,snapshot) values(cid,'2026-11-01','locked','synthetic','{}');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',principals[2],'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',leaves[3],'decision','cancelled'));exception when others then caught=true;end;
 if not caught then raise exception 'Locked payroll cancellation permitted';end if;
 -- Reassigning an office revokes old approval authority immediately without broadening payroll access.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 insert into auth.users(id,email,email_confirmed_at) values(replacement,'qa-new-office@example.invalid',now());
 insert into public.payroll_members values(cid,replacement,'manager');
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','director','email','qa-new-office@example.invalid'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',principals[2],'role','authenticated')::text,true);
 if payroll_private.leave_can_decide(leaves[3]) then raise exception 'Former office retained authority';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',replacement,'role','authenticated')::text,true);
 if not payroll_private.leave_can_decide(leaves[3]) then raise exception 'New office missing authority';end if;
 -- Separated officer immediately loses authority and is shown unavailable.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 update public.payroll_staff set status='separated' where company_id=cid and user_id=principals[1];
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if exists(select 1 from jsonb_array_elements(j->'leave_routing'->'offices') x where x->>'office'='principal' and (x->>'ready')::boolean) then raise exception 'Inactive officer shown ready';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',workers[1],'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',staffids[1],'leave_type','CL','from_date','2026-12-01','to_date','2026-12-01','half_day',false,'reason','Inactive approver'));exception when others then caught=true;end;
 if not caught then raise exception 'Inactive approver route accepted';end if;
 update public.payroll_staff set status='active' where company_id=cid and user_id=principals[1];
 -- Missing and self-directed approval routes fail before creating a new request.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email',''));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',workers[1],'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',staffids[1],'leave_type','CL','from_date','2026-12-01','to_date','2026-12-01','half_day',false,'reason','Missing approver'));exception when others then caught=true;end;
 if not caught then raise exception 'Missing approver request accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email','qa-leave-worker-1@example.invalid'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',workers[1],'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',staffids[1],'leave_type','CL','from_date','2026-12-01','to_date','2026-12-01','half_day',false,'reason','Self route'));exception when others then caught=true;end;
 if not caught then raise exception 'Self-directed approval route accepted';end if;
end$$;
select 'PASS: approval matrix, permissions, RLS, balances, snapshots, reassignment and lock guards' as result;
rollback;
