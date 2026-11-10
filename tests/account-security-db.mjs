import {PGlite} from '@electric-sql/pglite'
import {readFile} from 'node:fs/promises'
import assert from 'node:assert/strict'
const db=new PGlite()
try{
 await db.exec(`create schema auth;create schema private;create schema payroll_private;create table auth.users(id uuid primary key,raw_app_meta_data jsonb default '{}',deleted_at timestamptz,banned_until timestamptz);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create table pm_login_accounts(user_id uuid,password_change_required boolean);create table payroll_members(company_id uuid,user_id uuid,role text);create table payroll_staff(company_id uuid,user_id uuid,status text);create table payroll_leave_approvers(company_id uuid,user_id uuid,office text);create table payroll_platform_admins(user_id uuid);`)
 const uid='10000000-0000-4000-8000-000000000001',cid='20000000-0000-4000-8000-000000000001'
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid])
 await db.query('insert into auth.users(id) values($1)',[uid])
 await db.query("insert into payroll_members values($1,$2,'admin')",[cid,uid])
 await db.query('insert into payroll_platform_admins values($1)',[uid])

 const migration=await readFile(new URL('../database/account-security-upgrade.sql',import.meta.url),'utf8')
 await db.exec(migration.split('-- PATCH\n')[1])
 const status=async()=>(await db.query('select payroll_private.role($1) as company_role,payroll_private.platform_admin() as platform',[cid])).rows[0]
 const allowed={company_role:'admin',platform:true},denied={company_role:null,platform:false}
 assert.deepEqual(await status(),allowed)

 await db.exec("update auth.users set banned_until=now()+interval '1 day'")
 assert.deepEqual(await status(),denied)
 await db.exec("update auth.users set banned_until=now()-interval '1 day'")
 assert.deepEqual(await status(),allowed)
 await db.exec('update auth.users set deleted_at=now()')
 assert.deepEqual(await status(),denied)
 await db.exec('delete from auth.users')
 assert.deepEqual(await status(),denied)
 await db.query('insert into auth.users(id,raw_app_meta_data) values($1,$2)',[uid,JSON.stringify({pm_managed_login:true,payroll_password_change_required:true})])
 assert.deepEqual(await status(),denied)
 console.log('PASS active account allowed; banned, soft-deleted, missing and temporary-password accounts denied')
}finally{await db.close()}

