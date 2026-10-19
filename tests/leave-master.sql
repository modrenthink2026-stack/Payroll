-- Synthetic fixtures only; no real employee requests or balances are changed.
begin;
do $$
declare owner_id uuid; cid uuid; othercid uuid; worker uuid=gen_random_uuid(); hr_id uuid=gen_random_uuid(); sid uuid; lid uuid; p jsonb; j jsonb; caught boolean; msg text;
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"Leave Master QA rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"Other leave tenant QA rollback"}')->>'id')::uuid;
 insert into auth.users(id,email,email_confirmed_at) values(worker,'qa-leave-master-worker@example.invalid',now()),(hr_id,'qa-leave-master-hr@example.invalid',now());
 insert into public.payroll_members values(cid,worker,'staff'),(cid,hr_id,'hr');
 insert into public.payroll_staff(company_id,code,name,email,joining_date,user_id,leave_group) values(cid,'LM-QA','Synthetic leave worker',null,'2026-10-01',worker,'teacher_staff') returning id into sid;
 insert into public.payroll_leave_approvers(company_id,office,user_id) values(cid,'principal',owner_id);
 p=jsonb_build_object('company_id',cid,'code',' pl ','name','Personal Leave','annual_entitlement',10,'paid',true,'active',true,'half_day_allowed',false,'max_days_per_request',2,'description','Synthetic reviewed policy','creating',true);
 perform public.payroll_api('leave_policy',p);
 if not exists(select 1 from public.payroll_leave_policies where company_id=cid and code='PL' and name='Personal Leave' and annual_entitlement=10 and not half_day_allowed and active and max_days_per_request=2) then raise exception 'Leave master fields not persisted';end if;
 if coalesce((select (leave_balances->>'PL')::numeric from public.payroll_staff where id=sid),0)<>0 then raise exception 'Policy automatically credited balance';end if;
 -- Invalid inputs, duplicate creation, immutable code and pay status are all rejected.
 for j in select * from jsonb_array_elements('[{"annual_entitlement":-1},{"annual_entitlement":1.25},{"annual_entitlement":367},{"code":"BAD CODE"},{"code":"X","name":""},{"max_days_per_request":0},{"max_days_per_request":1.25},{"max_days_per_request":367},{"code":"PL","paid":false,"creating":false},{"code":"NEW","original_code":"PL","creating":false},{}]') loop
  caught=false;begin perform public.payroll_api('leave_policy',p||j);exception when others then caught=true;end;
  if not caught then raise exception 'Invalid leave policy accepted: %',j;end if;
 end loop;
 -- HR can edit rules, but policy edits still never change balances.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_policy',p||jsonb_build_object('code','PL','creating',false,'original_code','PL','annual_entitlement',12));
 perform public.payroll_api('leave_credit',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','PL','units',3,'reason','Reviewed opening balance'));
 for j in select * from jsonb_array_elements('[{"leave_type":"UNKNOWN","units":1},{"leave_type":"LWP","units":1},{"leave_type":"PL","units":0},{"leave_type":"PL","units":0.25},{"leave_type":"PL","units":-4}]') loop
  caught=false;begin perform public.payroll_api('leave_credit',jsonb_build_object('company_id',cid,'staff_id',sid,'reason','Invalid adjustment QA')||j);exception when others then caught=true;end;
  if not caught then raise exception 'Invalid balance adjustment accepted';end if;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 caught=false;begin perform public.payroll_api('leave_policy',p||'{"creating":false}');exception when others then caught=true;end;if not caught then raise exception 'Staff edited Leave Master';end if;
 caught=false;begin perform public.payroll_api('leave_policy',p||jsonb_build_object('company_id',othercid,'creating',false));exception when others then caught=true;end;if not caught then raise exception 'Cross-company Leave Master write';end if;
 for j in select * from jsonb_array_elements('[{"from_date":"2026-11-02","to_date":"2026-11-02","half_day":true},{"from_date":"2026-11-02","to_date":"2026-11-04","half_day":false}]') loop
  caught=false;msg='';begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','PL','reason','Synthetic limit QA')||j);exception when others then caught=true;msg=sqlerrm;end;
  if not caught or position('half-day' in msg)=0 then raise exception 'Request limit not enforced: %',msg;end if;
 end loop;
 lid=(public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','PL','from_date','2026-11-02','to_date','2026-11-03','half_day',false,'reason','Synthetic two-day request'))->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_policy',p||jsonb_build_object('code','PL','creating',false,'active',false));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 caught=false;msg='';begin perform public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','PL','from_date','2026-11-05','to_date','2026-11-05','half_day',false,'reason','Synthetic inactive QA'));exception when others then caught=true;msg=sqlerrm;end;
 if not caught or position('inactive' in msg)=0 then raise exception 'Inactive leave was not rejected: %',msg;end if;
 -- Archiving never blocks existing decisions or changes the paid classification/refund.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',lid,'decision','approved'));
 if (select (leave_balances->>'PL')::numeric from public.payroll_staff where id=sid)<>1 then raise exception 'Approved custom paid leave debit wrong';end if;
 perform public.payroll_api('leave_decide',jsonb_build_object('company_id',cid,'id',lid,'decision','cancelled'));
 if (select (leave_balances->>'PL')::numeric from public.payroll_staff where id=sid)<>3 then raise exception 'Custom paid leave refund wrong';end if;
 perform public.payroll_api('leave_policy',p||jsonb_build_object('code','PL','creating',false,'active',true,'half_day_allowed',true,'max_days_per_request',0.5));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 lid=(public.payroll_api('leave_apply',jsonb_build_object('company_id',cid,'staff_id',sid,'leave_type','PL','from_date','2026-11-02','to_date','2026-11-02','half_day',true,'reason','Synthetic half-day boundary'))->>'id')::uuid;
 if not exists(select 1 from public.payroll_leaves where id=lid and units=0.5) then raise exception 'Allowed half-day boundary failed';end if;
end$$;
rollback;
select 'PASS: Leave Master create/edit, immutable code/pay classification, limits, half days, inactive types, HR/Staff and tenant permissions, custom balance credit/debit/refund, no automatic credits' as result;
