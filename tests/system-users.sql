-- Synthetic system-user setup and permissions; all writes roll back.
begin;
do $$
declare owner_id uuid;cid uuid=gen_random_uuid();other_cid uuid=gen_random_uuid();system_id uuid=gen_random_uuid();other_owner uuid=gen_random_uuid();reservation jsonb;plan jsonb;denied boolean;prefix text='qa.'||replace(gen_random_uuid()::text,'-','');payload jsonb;
begin
 select user_id into owner_id from public.payroll_members where role='admin' limit 1;if owner_id is null then raise exception 'Seed a confirmed admin';end if;
 insert into public.payroll_companies(id,name) values(cid,'System users QA rollback'),(other_cid,'Other system users QA rollback');
 insert into auth.users(id,email,email_confirmed_at) values(other_owner,prefix||'.owner@example.invalid',now());
 insert into public.payroll_members values(cid,owner_id,'admin'),(other_cid,other_owner,'admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 payload=jsonb_build_object('action','prepare','company_id',cid,'username',prefix,'name','Synthetic System User','role','accountant');
 reservation=public.payroll_system_users(payload);
 if exists(select 1 from public.payroll_staff where company_id=cid) or exists(select 1 from public.payroll_salaries where company_id=cid) then raise exception 'System reservation created employee or salary';end if;
 if public.payroll_system_users(payload) is distinct from reservation then raise exception 'Reservation retry changed identity';end if;
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values(system_id,reservation->>'email',now(),jsonb_build_object('payroll_system_user_id',reservation->>'id','payroll_company_id',cid,'payroll_password_change_required',true));
 plan=public.payroll_system_users(payload);if (plan->>'pending_user_id')::uuid<>system_id then raise exception 'Pending account retry lost identity';end if;
 denied=false;begin perform public.payroll_system_users(jsonb_build_object('action','link','company_id',other_cid,'id',reservation->>'id','user_id',system_id));exception when others then denied=true;end;if not denied then raise exception 'Cross-company linkage accepted';end if;
 perform public.payroll_system_users(jsonb_build_object('action','link','company_id',cid,'id',reservation->>'id','user_id',system_id,'role','admin'));
 if (select role from public.payroll_members where company_id=cid and user_id=system_id)<>'accountant' then raise exception 'Link changed reserved role';end if;
 if public.payroll_system_users(payload)->>'linked'<>'true' then raise exception 'Activated retry not detected';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',system_id,'role','authenticated')::text,true);
 if public.payroll_system_users('{"action":"password_ready"}')->>'ready'<>'true' then raise exception 'Nonemployee first-password flow failed';end if;
 if public.payroll_api('bootstrap','{}')->>'password_change_required'<>'true' then raise exception 'System user bypassed first-password gate';end if;
 denied=false;begin perform public.payroll_system_users(payload);exception when others then denied=true;end;if not denied then raise exception 'Temporary account created another user';end if;
 update auth.users set raw_app_meta_data=raw_app_meta_data||'{"payroll_password_change_required":false}' where id=system_id;
 if payroll_private.role(cid)<>'accountant' then raise exception 'Nonemployee has no assigned access';end if;
 denied=false;begin perform public.payroll_system_users(payload);exception when others then denied=true;end;if not denied then raise exception 'Accountant created another user';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_owner,'role','authenticated')::text,true);
 denied=false;begin perform public.payroll_system_users(payload||jsonb_build_object('company_id',other_cid));exception when others then denied=true;end;if not denied then raise exception 'Username stolen by another company';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 if payroll_private.staff_login_name(prefix,'QA')=prefix then raise exception 'Employee username collided with system login';end if;
 denied=false;begin insert into public.payroll_staff(company_id,code,name,email,joining_date,user_id) values(cid,'SYS-QA','Must not be employee',prefix||'.contact@example.invalid','2026-01-01',system_id);exception when others then denied=true;end;if not denied then raise exception 'System login linked to Staff Master';end if;
 denied=false;begin insert into public.payroll_staff(company_id,code,name,email,joining_date) values(cid,'MAIL-QA','Must not auto-link',reservation->>'email','2026-01-01');exception when others then denied=true;end;if not denied then raise exception 'System email could auto-link on bootstrap';end if;
 if exists(select 1 from public.payroll_staff where company_id=cid) or exists(select 1 from public.payroll_salaries where company_id=cid) or exists(select 1 from public.payroll_attendance where company_id=cid) then raise exception 'System user contaminated employee records';end if;
 if has_table_privilege('authenticated','payroll_private.system_users','insert') or has_table_privilege('anon','payroll_private.system_users','select') then raise exception 'Private account reservations exposed';end if;
end$$;
rollback;
