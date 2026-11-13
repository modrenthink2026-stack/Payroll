import test from 'node:test';import assert from 'node:assert/strict';import {accountFetch} from '../account-transport.mjs';
const app={kind:'payroll',supabaseUrl:'https://example.supabase.co'},url=app.supabaseUrl+'/functions/v1/payroll-accounts';
const options={method:'POST',headers:{Authorization:'Bearer synthetic-token','Content-Type':'application/json',apikey:'publishable-test'},body:JSON.stringify({action:'synthetic-test'})};
test('native account transport preserves token/JSON/status without changing server Origin allowlists',async()=>{
 let captured;const request=accountFetch(()=>{throw Error('Browser transport must not handle this endpoint');},async o=>{captured=o;return {data:{error:'Permission denied'},status:403,headers:{'Content-Type':'application/json'}};},app);
 const response=await request(url,options);assert.equal(response.status,403);assert.deepEqual(await response.json(),{error:'Permission denied'});assert.equal(captured.headers.authorization,'Bearer synthetic-token');assert.equal(captured.headers.origin,undefined);assert.deepEqual(captured.data,{action:'synthetic-test'});assert.equal(captured.disableRedirects,true);
});
test('native transport is limited to the exact Payroll endpoint and preserves normal fetch for blob and REST',async()=>{
 const calls=[];const request=accountFetch(async(input)=>{calls.push(input);return 'web';},()=>{throw Error('Unexpected native request');},app);
 for(const input of ['blob:https://localhost/test',app.supabaseUrl+'/rest/v1/rpc/payroll_api','https://other.example/functions/v1/payroll-accounts'])assert.equal(await request(input,options),'web');assert.equal(calls.length,3);
 const pm=accountFetch(async()=> 'web',()=>{throw Error('Unexpected native request');},{...app,kind:'project'});assert.equal(await pm(url,options),'web');
});
test('native account transport requires authenticated JSON and rejects canceled requests',async()=>{
 const request=accountFetch(()=>{},()=>{throw Error('Must reject before native request');},app);
 await assert.rejects(request(url,{...options,headers:{}}),/Sign in/);
 await assert.rejects(request(url,{...options,headers:{...options.headers,Origin:'https://example.com'}}),/override Origin/);
 await assert.rejects(request(url,{...options,body:undefined}),/JSON POST/);
 const controller=new AbortController();controller.abort();await assert.rejects(request(url,{...options,signal:controller.signal}),{name:'AbortError'});
});
