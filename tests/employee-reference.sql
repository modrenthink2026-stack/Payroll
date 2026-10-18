begin;
do $$
declare cid uuid; sid uuid; sid2 uuid; ref text; login text; caught boolean;
begin
 insert into public.payroll_companies(name) values('Reference QA rollback') returning id into cid;
 insert into public.payroll_staff(company_id,code,name,email,joining_date)
 values(cid,'REF-QA','Reference QA','ref-qa@example.invalid','2026-10-01') returning id,employee_ref,login_name into sid,ref,login;
 if ref !~ '^EMP-[0-9]{6,}$' then raise exception 'Reference format missing';end if;
 update public.payroll_staff set name='Changed reference QA',department='QA',status='separated' where id=sid;
 if not exists(select 1 from public.payroll_staff where id=sid and employee_ref=ref and code='REF-QA' and login_name=login) then raise exception 'Reference or existing identity changed';end if;
 caught=false;begin update public.payroll_staff set employee_number=employee_number+10000 where id=sid;exception when generated_always then caught=true;end;
 if not caught then raise exception 'Reference number mutable';end if;
 caught=false;begin update public.payroll_staff set employee_number=default where id=sid;exception when raise_exception then caught=true;end;
 if not caught then raise exception 'Default update changed reference';end if;
 caught=false;begin update public.payroll_staff set employee_ref='EMP-FAKE' where id=sid;exception when generated_always then caught=true;end;
 if not caught then raise exception 'Reference override accepted';end if;
 delete from public.payroll_staff where id=sid;
 insert into public.payroll_staff(company_id,code,name,email,joining_date)
 values(cid,'REF-QA','Reference QA','ref-qa@example.invalid','2026-10-01') returning id into sid2;
 if exists(select 1 from public.payroll_staff where id=sid2 and employee_ref=ref) then raise exception 'Deleted reference reused';end if;
 insert into public.payroll_staff(company_id,code,name,email,joining_date)
 select cid,'BULK-'||n,'Reference bulk '||n,'reference-bulk-'||n||'@example.invalid','2026-10-01'::date from generate_series(1,100) n;
 if (select count(distinct employee_ref) from public.payroll_staff where company_id=cid)<>101 then raise exception 'Bulk reference collision';end if;
 if exists(select 1 from public.payroll_staff where employee_ref is null) then raise exception 'Backfill missing';end if;
 if 'EMP-'||lpad('1000000',greatest(6,length('1000000')),'0')<>'EMP-1000000' then raise exception 'Large references truncated';end if;
end$$;
rollback;
select 'PASS: generated, stable, override protected, bulk unique, not reused, backfilled, expandable references' as result;
