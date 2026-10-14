import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {config} from '../public/config.js';

test('password authentication, payroll data and logout use the same-origin proxy',async()=>{
 const values=new Map();globalThis.sessionStorage={getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v)};
 const requests=[];
 const jwt=Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+3600})).toString('base64url');
 const session={access_token:`test.${jwt}.signature`,refresh_token:'test-refresh',user:{id:'test-user'}};
 globalThis.fetch=async(url,options)=>{
  requests.push({url,options});
  return {ok:true,json:async()=>url.includes('/token?')?session:{ok:true}};
 };
 const api=await import('../public/api.js?proxy-test');
 await api.signIn('test@example.invalid','test-only-password');
 await api.rpc('state',{company_id:'test-company'});
 await api.signOut();
 assert.equal(requests[0].url,'/supabase/auth/v1/token?grant_type=password');
 assert.equal(requests[1].url,'/supabase/rest/v1/rpc/payroll_api');
 assert.equal(requests[2].url,'/supabase/auth/v1/logout');
 assert.equal(requests[0].options.headers.apikey,config.key);
 assert.equal(requests[1].options.headers.Authorization,`Bearer ${session.access_token}`);
 assert.equal(api.currentUser(),undefined);
});

test('Vercel proxy forwards only to this Supabase project and disables caching',async()=>{
 const v=JSON.parse(await readFile(new URL('../vercel.json',import.meta.url)));
 assert.deepEqual(v.rewrites,[{source:'/supabase/:path*',destination:'https://uvowltyjnzqtozygalhf.supabase.co/:path*'}]);
 const headers=v.headers.find(h=>h.source==='/supabase/:path*').headers;
 for(const name of ['Cache-Control','CDN-Cache-Control','Vercel-CDN-Cache-Control'])assert.ok(headers.some(h=>h.key===name&&h.value==='no-store'));
});
