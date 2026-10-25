import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';

const sql=file=>readFile(new URL('../'+file,import.meta.url),'utf8');
const db=new PGlite();
let failure;
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;
 create table auth.users(id uuid primary key,email text unique,email_confirmed_at timestamptz,raw_app_meta_data jsonb default '{}',raw_user_meta_data jsonb default '{}');
 create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
 grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;`);
 for(const file of ['payroll.sql','system-users-upgrade.sql','salary-payment-holds-upgrade.sql'])await db.exec(await sql('database/'+file));
 await db.exec(`insert into auth.users(id,email,email_confirmed_at) values('10000000-0000-0000-0000-000000000001','sql-owner@example.invalid',now());
 insert into public.payroll_companies(id,name) values('20000000-0000-0000-0000-000000000001','Synthetic SQL owner');
 insert into public.payroll_members values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin');`);
 const files=(await readdir(new URL('./',import.meta.url))).filter(f=>f.endsWith('.sql')&&f!=='platform-payment-controls.sql'&&f!=='monthly-attendance.sql').sort();
 for(const file of files){await db.exec(await sql('tests/'+file));console.log('PASS SQL '+file);}

 // Reproduce the older platform gateway, then repair it without losing records.
 await db.exec(`insert into public.payroll_staff(company_id,code,name,email,joining_date) values('20000000-0000-0000-0000-000000000001','PRESERVE','Synthetic preserved hold','preserved@example.invalid','2026-01-01');
 select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',false);
 select public.payroll_api('salary_hold_set',jsonb_build_object('company_id','20000000-0000-0000-0000-000000000001','staff_id',(select id from public.payroll_staff where code='PRESERVE'),'month','2026-10-01','status','held','reason','Preserve this existing payment hold','expected_revision',0,'request_id',gen_random_uuid()));`);
 const records=`select jsonb_build_object('staff',(select jsonb_agg(to_jsonb(s)) from public.payroll_staff s),'holds',(select jsonb_agg(to_jsonb(h)) from payroll_private.salary_payment_holds h),'events',(select jsonb_agg(to_jsonb(e)) from payroll_private.salary_payment_hold_events e),'audit',(select jsonb_agg(to_jsonb(a)) from public.payroll_audit a),'requests',(select jsonb_agg(to_jsonb(r)) from payroll_private.requests r)) state`;
 const saved=(await db.query(records)).rows;
 await db.exec(`create or replace function public.payroll_api(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select payroll_private.dispatch(action,payload)$$;`);
 const before=(await db.query('select id,company_id,user_id,role from (select company_id as id,* from public.payroll_members) m order by id,user_id')).rows;
 await db.exec(await sql('supabase/migrations/20261024123135_payroll_reliability.sql'));
 await db.exec(await sql('supabase/migrations/20261025170000_monthly_attendance_import.sql'));
 await db.exec(await sql('tests/monthly-attendance.sql'));
 console.log('PASS SQL monthly-attendance.sql');
 assert.deepEqual((await db.query(records)).rows,saved);
 await db.exec(await sql('tests/salary-payment-holds.sql'));
 await db.exec(await sql('tests/platform-payment-controls.sql'));
 assert.deepEqual((await db.query('select id,company_id,user_id,role from (select company_id as id,* from public.payroll_members) m order by id,user_id')).rows,before);
 assert.equal((await db.query('select count(*)::int n from public.payroll_platform_admins')).rows[0].n,0);
 console.log('PASS repair migration preserves memberships and grants no platform access');

 // Verify both the documented fresh install and the reverse upgrade order.
 for(const reverse of [false,true]){
 const reordered=new PGlite();
 try{
  await reordered.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_app_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;`);
  if(reverse){for(const file of ['payroll.sql','system-users-upgrade.sql','platform-admin-upgrade.sql','salary-payment-holds-upgrade.sql','monthly-attendance-upgrade.sql'])await reordered.exec(await sql('database/'+file));}
  else await reordered.exec(execFileSync(process.execPath,['scripts/database-install.mjs'],{encoding:'utf8',maxBuffer:2_000_000}));
  assert.ok((await reordered.query(`select pg_get_functiondef('public.payroll_api(text,jsonb)'::regprocedure) source`)).rows[0].source.includes('platform_action_guard'));
  await reordered.exec(`insert into auth.users(id,email,email_confirmed_at) values('10000000-0000-0000-0000-000000000001','reordered@example.invalid',now());insert into public.payroll_companies(id,name) values('20000000-0000-0000-0000-000000000001','Reordered');insert into public.payroll_members values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin');`);
  await reordered.exec(await sql('tests/salary-payment-holds.sql'));
  await reordered.exec(await sql('tests/platform-payment-controls.sql'));
  await reordered.exec(await sql('tests/monthly-attendance.sql'));
  console.log(reverse?'PASS reversed platform/payment upgrade order':'PASS complete fresh installation');
 }finally{await reordered.close();}
 }
 console.log(`PASS ${files.length+1} SQL suites plus repair and upgrade-order checks; synthetic in-memory data only.`);
}catch(error){failure=error;}
finally{await db.close();}
if(failure){console.error('FAIL SQL: '+failure.message);process.exitCode=1;}
