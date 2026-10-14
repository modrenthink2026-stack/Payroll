import test from 'node:test';
import assert from 'node:assert/strict';
import {parseRecoveryLink,isRecoveryCallback} from '../public/recovery.js';
const origin='https://payroll-git-main-chandu-7362.vercel.app';
test('email recovery links parse only for the correct Auth service',()=>{
 assert.deepEqual(parseRecoveryLink('https://uvowltyjnzqtozygalhf.supabase.co/auth/v1/verify?token=example-test-hash&type=recovery&redirect_to=https://other.example',origin),{type:'hash',token_hash:'example-test-hash'});
 assert.throws(()=>parseRecoveryLink('https://attacker.example/?token=example-test-hash&type=recovery',origin));
 assert.throws(()=>parseRecoveryLink('https://uvowltyjnzqtozygalhf.supabase.co/auth/v1/verify?token=example-test-hash&type=signup',origin));
 assert.throws(()=>parseRecoveryLink(origin+'/#error_description=expired',origin),/expired/);
});
test('callback detection distinguishes recovery from ordinary sign-in',()=>{
 assert.ok(isRecoveryCallback(origin+'/#type=recovery&access_token=test&refresh_token=test'));
 assert.equal(isRecoveryCallback(origin+'/'),false);
 assert.equal(isRecoveryCallback(origin+'/#type=signup'),false);
});
test('reset request uses the same-origin proxy and enforces resend cooldown',async()=>{
 const values=new Map(),calls=[];
 globalThis.sessionStorage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v)};
 globalThis.fetch=async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>({})};};
 const api=await import('../public/api.js?reset-email-test');
 await api.requestPasswordReset(' Staff@Example.invalid ',origin);
 assert.equal(calls[0].url,'/supabase/auth/v1/recover?redirect_to='+encodeURIComponent(origin+'/?recovery=1'));
 assert.deepEqual(JSON.parse(calls[0].options.body),{email:'staff@example.invalid'});
 await assert.rejects(api.requestPasswordReset('staff@example.invalid',origin),/one minute/);
 assert.equal(calls.length,1);
});
test('recovery session is validated by Auth before enabling password update',async()=>{
 const values=new Map(),calls=[];
 globalThis.sessionStorage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v)};
 const jwt=Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+3600})).toString('base64url');
 const token=`test.${jwt}.signature`;
 globalThis.fetch=async(url,options)=>{
  calls.push({url,options});
  const result=url.endsWith('/verify')?{access_token:token,refresh_token:'refresh-test'}:options.method==='PUT'?{id:'verified-user'}:{id:'verified-user',email:'staff@example.invalid'};
  return{ok:true,json:async()=>result};
 };
 const api=await import('../public/api.js?recovery-session-test');
 await api.acceptRecoveryLink('https://uvowltyjnzqtozygalhf.supabase.co/auth/v1/verify?token=test-recovery-hash&type=recovery',origin);
 assert.equal(calls[0].url,'/supabase/auth/v1/verify');
 assert.equal(calls[1].url,'/supabase/auth/v1/user');
 assert.equal(api.currentUser().id,'verified-user');
 assert.equal(api.recoveryActive(),true);
 await api.changePassword('new-test-password-123');
 assert.equal(calls[2].options.method,'PUT');
 assert.equal(calls[2].options.headers.Authorization,`Bearer ${token}`);
 await api.signOut();assert.equal(api.recoveryActive(),false);
});
test('invalid recovery credentials never replace the existing session',async()=>{
 const values=new Map();globalThis.sessionStorage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v)};
 globalThis.fetch=async()=>({ok:false,json:async()=>({message:'Expired'})});
 const api=await import('../public/api.js?recovery-invalid-test');
 await assert.rejects(api.acceptRecoveryLink('https://uvowltyjnzqtozygalhf.supabase.co/auth/v1/verify?token=test-expired-hash&type=recovery',origin));
 assert.equal(api.currentUser(),undefined);assert.equal(api.recoveryActive(),false);
});
