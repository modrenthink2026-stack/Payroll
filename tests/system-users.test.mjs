import test from 'node:test';import assert from 'node:assert/strict';
import {createHandler} from '../functions/payroll-accounts/handler.js';
const origin='https://payroll-orpin-one.vercel.app';
const request=b=>new Request(origin+'/accounts',{method:'POST',headers:{origin,authorization:'Bearer caller-token','Content-Type':'application/json'},body:JSON.stringify(b)});
const reply=(d,status=200)=>new Response(JSON.stringify(d),{status,headers:{'Content-Type':'application/json'}});
const make=f=>createHandler({url:'https://auth.example.invalid',publicKey:'public',adminKey:'private',fetcher:f});
const input={action:'create_system_user',company_id:'company',name:'Test Accountant',username:'testing.accounts',role:'accountant',password:'Synthetic-Only-123'};
test('System user authorization occurs before Auth administration and never creates an employee',async()=>{
 const calls=[];const h=make(async(url,opts)=>{const body=opts.body?JSON.parse(opts.body):{};calls.push({url,body,auth:opts.headers.Authorization});
  if(url.endsWith('/auth/v1/user'))return reply({id:'admin'});
  if(body.payload?.action==='prepare')return reply({id:'reservation',username:input.username,email:input.username+'@staff.payroll.invalid',linked:false});
  if(url.endsWith('/admin/users'))return reply({id:'system-account'});
  if(body.payload?.action==='link')return reply({ok:true});throw Error('Unexpected call');
 });const r=await h(request(input));assert.equal(r.status,200);const response=await r.json();assert.equal(response.username,input.username);
 assert.equal(calls[1].body.payload.action,'prepare');assert.equal(calls[1].auth,'Bearer caller-token');
 const creation=calls.find(c=>c.url.endsWith('/admin/users'));assert.equal(creation.body.app_metadata.payroll_system_user_id,'reservation');assert.equal(creation.body.app_metadata.payroll_password_change_required,true);assert.ok(!('payroll_staff_id' in creation.body.app_metadata));assert.equal(calls.at(-1).body.payload.action,'link');assert.ok(!JSON.stringify(response).includes(input.password));assert.ok(calls.every(c=>!c.body.action?.startsWith('staff_')));
});
test('Unauthorized system user creation never calls Auth administration',async()=>{
 const urls=[];const h=make(async(url)=>{urls.push(url);return url.endsWith('/auth/v1/user')?reply({id:'hr'}):reply({message:'Full company access required'},403)});assert.equal((await h(request(input))).status,403);assert.ok(urls.every(u=>!u.includes('/admin/users')));
});
test('Retries preserve already-created accounts and never reset their passwords',async()=>{
 for(const plan of [{linked:true,username:input.username},{linked:false,id:'reservation',username:input.username,pending_user_id:'pending'}]){
  const urls=[];const h=make(async(url,opts)=>{urls.push(url);if(url.endsWith('/auth/v1/user'))return reply({id:'admin'});const b=JSON.parse(opts.body);return reply(b.payload.action==='prepare'?plan:{ok:true});});assert.equal((await h(request(input))).status,200);assert.ok(urls.every(u=>!u.includes('/admin/users')));
 }
});
test('System users must pass the dedicated first-login readiness check before changing password',async()=>{
 const calls=[];const h=make(async(url,opts)=>{const b=opts.body?JSON.parse(opts.body):{};calls.push({url,b});return opts.method==='GET'?reply({id:'sys',app_metadata:{payroll_system_user_id:'reservation',payroll_password_change_required:true}}):reply({id:'sys'})});assert.equal((await h(request({action:'change_password',password:'Synthetic-New-123'}))).status,200);assert.ok(calls[1].url.endsWith('/rpc/payroll_system_users'));assert.equal(calls[1].b.payload.action,'password_ready');assert.ok(calls[2].url.endsWith('/auth/v1/user'));assert.equal(calls[3].b.app_metadata.payroll_password_change_required,false);
});
test('Platform administrator provisioning uses the cross-company RPC and keeps the password out of responses',async()=>{
 const calls=[];const h=make(async(url,opts)=>{const body=opts.body?JSON.parse(opts.body):{};calls.push({url,body});
  if(url.endsWith('/auth/v1/user'))return reply({id:'platform-owner'});
  if(body.payload?.action==='prepare')return reply({id:'reservation',username:'company.admin',email:'company.admin@staff.payroll.invalid',linked:false});
  if(url.endsWith('/admin/users'))return reply({id:'company-admin'});
  if(body.payload?.action==='link')return reply({ok:true});throw Error('Unexpected call');
 });
 const r=await h(request({...input,platform_admin:true,company_id:'other-company',username:'company.admin'}));
 assert.equal(r.status,200);assert.equal(calls[1].url,'https://auth.example.invalid/rest/v1/rpc/payroll_platform_user');assert.equal(calls.at(-1).url,'https://auth.example.invalid/rest/v1/rpc/payroll_platform_user');assert.ok(!JSON.stringify(await r.json()).includes(input.password));
});
