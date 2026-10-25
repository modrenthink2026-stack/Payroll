import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';

const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
const loadSource=source.slice(source.indexOf('async function load(){'),source.indexOf('function login('));
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
function harness(platformAdmin=async()=>null){
 const pending=new Map(),renders=[],warnings=[],app={innerHTML:''};
 const context=vm.createContext({app,platformAdmin,modal:{close(){}},toast:message=>warnings.push(message),
  rpc:async(action,payload)=>action==='bootstrap'?{companies:[{id:'a'},{id:'b'}]}:(pending.set(payload.company_id,deferred()),pending.get(payload.company_id).promise),
  firstPasswordScreen(){},renderPlatform(){},render(){renders.push({company:context.company.id,data:context.data.company_id});},
  company:{id:'a'},companies:[],data:{company_id:'old'},platform:null,loadGeneration:0});
 vm.runInContext(loadSource+';globalThis.load=load;',context);
 return {context,pending,renders,warnings,app};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));

test('Company loads discard late responses and clear the previous workspace immediately',async()=>{
 const {context,pending,renders,app}=harness();
 const a=context.load();assert.equal(Object.keys(context.data).length,0);assert.ok(app.innerHTML.includes('Loading company'));
 await tick();context.company={id:'b'};const b=context.load();await tick();
 pending.get('b').resolve({company_id:'b'});await b;pending.get('a').resolve({company_id:'a'});await a;
 assert.deepEqual(renders,[{company:'b',data:'b'}]);assert.equal(context.data.company_id,'b');
});

test('Late load failures cannot replace the current workspace or show stale errors',async()=>{
 const {context,pending,renders}=harness();const a=context.load();await tick();
 context.company={id:'b'};const b=context.load();await tick();pending.get('b').resolve({company_id:'b'});await b;
 pending.get('a').reject(Error('old request failed'));await a;assert.equal(renders.length,1);
});

test('Missing platform infrastructure is visible while normal company access still works',async()=>{
 for(const message of ['Could not find the function public.payroll_platform_admin','Platform administrator access required']){
  const {context,pending,warnings}=harness(async()=>{throw Error(message);});const loading=context.load();await tick();
  pending.get('a').resolve({company_id:'a'});await loading;
  assert.equal(warnings.length,message==='Platform administrator access required'?0:1);
 }
});

test('A current state failure is reported and an invalidated session never renders',async()=>{
 const {context,pending,renders}=harness();const failed=context.load();await tick();pending.get('a').reject(Error('offline'));
 await assert.rejects(failed,/offline/);
 const loading=context.load();await tick();context.loadGeneration++;context.company=null;pending.get('a').resolve({company_id:'a'});await loading;
 assert.equal(renders.length,0);
});

test('The default payroll month follows India time across UTC month boundaries',()=>{
 const expression=source.match(/month=(.*?),search=''/)[1];
 for(const [instant,expected] of [['2026-11-01T00:30:00+05:30','2026-11'],['2027-01-01T00:01:00+05:30','2027-01'],['2026-10-31T23:59:00+05:30','2026-10']]){
  const Clock=class extends Date{constructor(){super(instant);}};
  assert.equal(vm.runInNewContext(expression,{Date:Clock}),expected);
 }
});
