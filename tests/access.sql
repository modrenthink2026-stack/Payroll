-- Synthetic identities, scopes and roles only. Everything rolls back.
begin;
do $$
declare uid uuid;cid uuid;othercid uuid;worker uuid=gen_random_uuid();hr_uid uuid=gen_random_uuid();principal uuid=gen_random_uuid();president uuid=gen_random_uuid();reader uuid=gen_random_uuid();sid uuid;sid2 uuid;r1 uuid;r2 uuid;j jsonb;bad boolean;k text;u uuid;
begin
 select user_id into uid from public.payroll_members where role='admin' limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(worker,'qa-access-worker@example.invalid',now()),(hr_uid,'qa-access-hr@example.invalid',now()),(principal,'qa-access-principal@example.invalid',now()),(president,'qa-access-president@example.invalid',now()),(reader,'qa-access-reader@example.invalid',now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 cid=(public.payroll_api('company_create','{"name":"QA access rollback"}')->>'id')::uuid;
 othercid=(public.payroll_api('company_create','{"name":"QA isolated tenant rollback"}')->>'id')::uuid;
 insert into public.payroll_members values(cid,worker,'staff'),(cid,hr_uid,'hr'),(cid,principal,'principal'),(cid,president,'president');
 sid=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','ACCESS-1','name','Synthetic Same Name','email','qa-access-worker@example.invalid','joining_date','2026-10-01','basic',31000,'da',0,'hra',0,'other',0))->>'id')::uuid;
 sid2=(public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','ACCESS-2','name','Synthetic Same Name','email','qa-access-second@example.invalid','joining_date','2026-10-01','basic',31000,'da',0,'hra',0,'other',0))->>'id')::uuid;
 update public.payroll_staff set user_id=worker where id=sid;
 if (select count(distinct login_name) from public.payroll_staff where company_id=cid)<>2 then raise exception 'Duplicate names created ambiguous Login IDs';end if;
 insert into public.payroll_staff_details(company_id,staff_id,details) values(cid,sid,'{"Address":"Synthetic private address"}');
 insert into public.payroll_attendance(company_id,staff_id,work_date,status) values(cid,sid,'2026-10-01','present');
 insert into public.payroll_documents(company_id,staff_id,type,recipient,body,signatory,status) values(cid,sid,'Example','Synthetic','Synthetic issued letter','QA','issued');
 insert into public.payroll_runs(company_id,month,status,input_hash,snapshot) values(cid,'2026-10-01','released','QA','{}') returning id into r1;
 insert into public.payroll_runs(company_id,month,status,input_hash,snapshot) values(cid,'2026-11-01','released','QA','{}') returning id into r2;
 insert into public.payroll_lines(company_id,run_id,staff_id,earnings,deductions,employer,gross,net,paid_days,lop,staff_snapshot) values(cid,r1,sid,'{}','{}','{}',31000,31000,31,0,'{}'),(cid,r2,sid2,'{}','{}','{}',31000,31000,31,0,'{}');
 -- Staff state contains own leave inputs and own released payslips only.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if jsonb_array_length(j->'staff')<>1 or jsonb_array_length(j->'lines')<>1 or jsonb_array_length(j->'runs')<>1 then raise exception 'Staff own-record/payslip isolation failed';end if;
 foreach k in array array['profiles','salaries','staff_details','attendance','punches','documents','assessments','increments','deposits'] loop
  if j->k<>'[]'::jsonb then raise exception 'Staff data escaped scope: %',k;end if;
 end loop;
 foreach k in array array['attendance_report','late_month','staff_save','member_grant','document_save','payroll_calculate','tax_inputs'] loop
  bad=false;begin perform public.payroll_api(k,jsonb_build_object('company_id',cid,'month','2026-10-01'));exception when others then bad=true;end;
  if not bad then raise exception 'Staff used forbidden action %',k;end if;
 end loop;
 j=public.payroll_api('bootstrap','{}');if (j->'companies'->0->'settings') ? 'pf_rate' then raise exception 'Staff bootstrap exposed unrelated settings';end if;
 execute 'set local role authenticated';
 if exists(select 1 from public.payroll_profiles where company_id=cid) or exists(select 1 from public.payroll_salaries where company_id=cid) or exists(select 1 from public.payroll_staff_details where company_id=cid) or exists(select 1 from public.payroll_documents where company_id=cid) or exists(select 1 from public.payroll_attendance where company_id=cid) then raise exception 'Direct Staff RLS escaped module boundaries';end if;
 if (select count(*) from public.payroll_runs where company_id=cid)<>1 or (select count(*) from public.payroll_lines where company_id=cid)<>1 then raise exception 'Direct Staff payslip RLS failed';end if;
 execute 'reset role';
 -- HR sees personnel, attendance, leave and letters but no payroll/salary workflow.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_uid,'role','authenticated')::text,true);
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));
 if jsonb_array_length(j->'staff')<>2 or jsonb_array_length(j->'profiles')<>2 or jsonb_array_length(j->'documents')<>1 or jsonb_array_length(j->'attendance')<>1 then raise exception 'HR required scope missing';end if;
 foreach k in array array['salaries','assessments','increments','deposits','runs','lines'] loop if j->k<>'[]'::jsonb then raise exception 'HR accessed forbidden data %',k;end if;end loop;
 foreach k in array array['member_grant','settings','payroll_calculate','initial_salary','tax_inputs','assessment_save','increment_save','staff_import'] loop
  bad=false;begin perform public.payroll_api(k,jsonb_build_object('company_id',cid));exception when others then bad=true;end;
  if not bad then raise exception 'HR used forbidden action %',k;end if;
 end loop;
 perform public.payroll_api('staff_save',jsonb_build_object('company_id',cid,'code','HR-ENTRY','name','Synthetic HR Entry','joining_date','2026-10-01'));
 if exists(select 1 from public.payroll_salaries where staff_id in(select id from public.payroll_staff where company_id=cid and code='HR-ENTRY')) then raise exception 'HR personnel entry invented salary';end if;
 execute 'set local role authenticated';if exists(select 1 from public.payroll_salaries where company_id=cid) or exists(select 1 from public.payroll_lines where company_id=cid) then raise exception 'Direct HR payroll RLS escaped scope';end if;execute 'reset role';
 -- Principal and President have full access only in their authorized company.
 foreach u in array array[principal,president] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  j=public.payroll_api('state',jsonb_build_object('company_id',cid));
  if jsonb_array_length(j->'staff')<>3 or jsonb_array_length(j->'salaries')<>2 or jsonb_array_length(j->'lines')<>2 then raise exception 'Full-access role incomplete';end if;
  bad=false;begin perform public.payroll_api('state',jsonb_build_object('company_id',othercid));exception when others then bad=true;end;
  if not bad then raise exception 'Full-access role crossed companies';end if;
 end loop;
 -- Office changes also update access immediately; no stale JWT role grants remain.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email','qa-access-hr@example.invalid'));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_uid,'role','authenticated')::text,true);
 if payroll_private.role(cid)<>'admin' or payroll_private.display_role(cid)<>'principal' then raise exception 'Principal office did not receive requested full access';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('leave_approver_set',jsonb_build_object('company_id',cid,'office','principal','email',''));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',hr_uid,'role','authenticated')::text,true);
 if payroll_private.role(cid)<>'hr' then raise exception 'Former Principal retained elevated access';end if;
 -- Activation only binds a marked account to its exact staff identity and company.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 j=public.payroll_api('staff_login_prepare',jsonb_build_object('company_id',cid,'staff_id',sid2));
 update auth.users set email=j->>'email',raw_app_meta_data=jsonb_build_object('payroll_staff_id',sid2,'payroll_company_id',cid,'payroll_password_change_required',true) where id=reader;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reader,'role','authenticated')::text,true);
 bad=false;begin perform public.payroll_api('staff_password_ready','{}');exception when others then bad=true;end;if not bad then raise exception 'Unlinked pending account passed first-password binding check';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 perform public.payroll_api('staff_login_link',jsonb_build_object('company_id',cid,'staff_id',sid2,'user_id',reader));
 perform set_config('request.jwt.claims',jsonb_build_object('sub',reader,'role','authenticated')::text,true);
 j=public.payroll_api('bootstrap','{}');if not (j->>'password_change_required')::boolean then raise exception 'First-login password gate missing';end if;
 if not (public.payroll_api('staff_password_ready','{}')->>'ready')::boolean then raise exception 'Linked account blocked from required password update';end if;
 bad=false;begin perform public.payroll_api('state',jsonb_build_object('company_id',cid));exception when others then bad=true;end;if not bad then raise exception 'Temporary-password session accessed data';end if;
 execute 'set local role authenticated';if exists(select 1 from public.payroll_staff where company_id=cid) or exists(select 1 from public.payroll_lines where company_id=cid) then raise exception 'Temporary-password session bypassed direct RLS';end if;execute 'reset role';
 update auth.users set raw_app_meta_data=raw_app_meta_data||'{"payroll_password_change_required":false}' where id=reader;
 j=public.payroll_api('state',jsonb_build_object('company_id',cid));if jsonb_array_length(j->'staff')<>1 then raise exception 'Activated staff account did not receive own-only access';end if;

end$$;
select 'PASS: duplicate-name Login IDs, Staff/HR scope, own released payslips, full Principal/President access, tenant isolation and immediate role revocation' as result;
rollback;
