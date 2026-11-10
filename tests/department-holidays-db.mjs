import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs/promises';
const root=new URL('../',import.meta.url).pathname;
const db=new PGlite();const quote=s=>'"'+s.replaceAll('"','""')+'"';
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_app_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;`);
 await db.exec(await fs.readFile(root+'/database/payroll.sql','utf8'));
 const schema=JSON.parse(await fs.readFile(root+'/tests/fixtures/holiday-schema.json','utf8'));
 for(const table of schema){
  const qualified=quote(table.schema)+'.'+quote(table.name);
  await db.exec('create table if not exists '+qualified+'()');
  const known=(await db.query(`select column_name from information_schema.columns where table_schema=$1 and table_name=$2`,[table.schema,table.name])).rows.map(x=>x.column_name);
  for(const col of table.columns)if(!known.includes(col.name)){
   let clause='';if(col.generated==='s')clause=' generated always as ('+col.default+') stored';else if(col.default&&!col.default.includes('nextval(')&&!col.default.includes('payroll_private.'))clause=' default '+col.default;
   await db.exec('alter table '+qualified+' add column '+quote(col.name)+' '+col.type+clause);
  }
 }
 await db.exec(`create or replace function payroll_private.module_enabled(cid uuid,module text) returns boolean language sql stable as $$select coalesce((enabled_modules->>module)::boolean,false) from public.payroll_companies where id=cid$$;create or replace function payroll_private.feature_enabled(cid uuid,feature text) returns boolean language sql stable as $$select false$$;`);
 await db.exec(await fs.readFile(root+'/tests/fixtures/holiday-hashes.sql','utf8'));
 const migration=await fs.readFile(root+'/supabase/migrations/20261110075724_department_holidays.sql','utf8');
 const guard=migration.match(/-- BEGIN CORE VERSION GUARD[\s\S]*?-- END CORE VERSION GUARD/)[0];
 let staleBlocked=false;try{await db.exec(guard);}catch(error){staleBlocked=error.message.includes('Payroll functions changed');}
 if(!staleBlocked)throw Error('Expected production version guard to reject the older local baseline');
 // The local schema fixture intentionally has an older baseline. Test business
 // behavior separately; the deployment SQL retains this guard without changes.
 await db.exec(migration.replace(guard,''));
 await db.exec(`insert into auth.users(id,email,email_confirmed_at) values('10000000-0000-0000-0000-000000000001','holiday-owner@example.invalid',now());insert into payroll_companies(id,name) values('20000000-0000-0000-0000-000000000001','Local fixture owner');insert into payroll_members values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','admin');`);
 await db.exec(await fs.readFile(root+'/tests/integration/department-holidays.sql','utf8'));
 console.log('PASS isolated holiday integration: scope, ranges, legacy dates, permissions, revisions, leave/confirmation locks, late exemptions, leave counts, cancellation and hashes.');
}catch(e){console.error(JSON.stringify({message:e.message,detail:e.detail,where:e.where}));process.exitCode=1;}finally{await db.close();}
