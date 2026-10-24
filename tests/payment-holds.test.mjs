import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {esc,money,csvText} from '../public/domain.js';
import {fullAccess,pagesFor} from '../public/access.js';
const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
function harness(role='admin',newline='\n'){
 const output={forms:[],shows:[],downloads:[],calls:[]};
 const document={documentElement:{dataset:{}},querySelector:s=>s==='#modal'?modal:{textContent:''}},modal={close(){},querySelectorAll:()=>[]};
 const context=vm.createContext({document,Date,console,esc,money,csvText,fullAccess,pagesFor,localStorage:{getItem:()=>null},rpc:async(action,payload)=>{output.calls.push({action,payload});return {held_count:1,paid_count:0,rows:[{name:'Payable Staff',bank_account:'00123456789',ifsc:'SBIN0001234',net:19000}]}}});
 vm.runInContext(source.replace(/\r?\n/g,newline).replace(/^import .*;\r?\n/gm,'').split("document.addEventListener('click'")[0]+`;globalThis.api={action,showHoldAuthorization,salaryPaymentCell,set:(d,r)=>{data=d;company={id:'c1',role:r};month='2026-10'}};form=(title,html,submit)=>captureForm(title,html,submit);show=(title,html)=>captureShow(title,html);download=(name,text)=>captureDownload(name,text);toast=()=>{};mutate=(a,p)=>captureMutation(a,p);`,context);
 context.captureForm=(title,html,submit)=>output.forms.push({title,html,submit});context.captureShow=(title,html)=>output.shows.push({title,html});context.captureDownload=(name,text)=>output.downloads.push({name,text});context.captureMutation=(a,p)=>output.calls.push({action:a,payload:p});
 const run={id:'r1',month:'2026-10-01',status:'released'},data={staff:[{id:'a',name:'Held Staff',code:'A1'},{id:'b',name:'Payable Staff',code:'B1'}],profiles:[],runs:[run],lines:[{id:'l1',staff_id:'a',run_id:'r1',net:10000},{id:'l2',staff_id:'b',run_id:'r1',net:19000}],salary_holds:[]};context.api.set(data,role);return {api:context.api,context,output,data,run};
}
test('HR and Accountant can hold before payroll exists without exposing salary to HR',async()=>{
 for(const role of ['hr','accountant']){const {api,output,data}=harness(role);api.showHoldAuthorization('a','2026-11');assert.equal(output.forms.length,1);assert.ok(output.forms[0].html.includes('minlength="5"'));await output.forms[0].submit({reason:'Pending authorized review'});assert.equal(output.calls.at(-1).payload.status,'held');assert.equal(output.calls.at(-1).payload.month,'2026-11-01');assert.equal(output.calls.at(-1).payload.expected_revision,0);
  if(role==='hr'){api.showHoldAuthorization('a','2026-10');assert.ok(!output.forms.at(-1).html.includes('Net salary'));}
 }
});

test('Payment checks run with both LF and Windows CRLF sources',async()=>{
 for(const newline of ['\n','\r\n']){const {api,output}=harness('accountant',newline);await api.action('bank-download','r1');assert.equal(output.downloads.length,1);}
});

test('A late bank response cannot download data after the company or session changes',async()=>{
 const {api,context,output}=harness();let finish;
 context.rpc=()=>new Promise(resolve=>{finish=resolve;});const pending=api.action('bank-download','r1');
 vm.runInContext('loadGeneration++',context);finish({rows:[{name:'Old company',bank_account:'00123456789',ifsc:'SBIN0001234',net:100}]});await pending;
 assert.equal(output.downloads.length,0);assert.equal(output.shows.length,0);
});

test('Unavailable backend payment rows cannot fall back to payroll lines',async()=>{
 const {api,context,output}=harness();context.rpc=async()=>({});
 await assert.rejects(api.action('bank-download','r1'),/Payment eligibility is unavailable/);assert.equal(output.downloads.length,0);
});

test('Logout removes the workspace before waiting for the network',async()=>{
 const {api,context}=harness();let finish;
 context.signOut=()=>new Promise(resolve=>{finish=resolve;});context.login=()=>{};
 const pending=api.action('logout');assert.match(vm.runInContext('app.innerHTML',context),/Signing out/);
 assert.equal(vm.runInContext('company',context),null);finish();await pending;
});
test('Only full-access company roles can release; paid salary cannot be held',()=>{
 for(const role of ['hr','accountant','admin','principal','president']){const {api,output,data,run}=harness(role);data.salary_holds=[{staff_id:'a',month:'2026-10-01',status:'held',reason:'Awaiting review',revision:1}];api.showHoldAuthorization('a','2026-10');
  if(['hr','accountant'].includes(role)){assert.equal(output.forms.length,0);assert.ok(!api.salaryPaymentCell(data.lines[0],run).includes('Release payment'));}else assert.equal(output.forms[0].title,'Release salary payment hold');
  data.lines[0].payment_reference='reconciled';assert.throws(()=>api.showHoldAuthorization('a','2026-10'),/already reconciled/);
 }
 for(const role of ['staff','manager','director'])assert.throws(()=>harness(role).api.showHoldAuthorization('a','2026-10'),/HR or Accountant/);
});
test('Bank downloads recheck backend eligibility and do not export held salaries',async()=>{
 const {api,output,data}=harness('accountant'),before=JSON.stringify(data);await api.action('bank-download','r1');assert.equal(output.calls[0].action,'salary_payment_state');assert.ok(output.downloads[0].text.includes('Payable Staff'));assert.ok(!output.downloads[0].text.includes('Held Staff'));assert.ok(output.downloads[0].text.endsWith('"19000.00"'));assert.equal(JSON.stringify(data),before);
});

test('Bank statements and downloads require released payroll and hold support',async()=>{
 for(const action of ['export-bank','bank-download']){
  for(const status of ['calculated','hr_reviewed','accountant_reviewed','locked','paid']){
   const {api,output,run}=harness();run.status=status;
   await assert.rejects(api.action(action,'r1'),/Release payroll/);assert.equal(output.calls.length,0);assert.equal(output.downloads.length,0);
  }
  const {api,output,data}=harness();delete data.salary_holds;
  await assert.rejects(api.action(action,'r1'),/Payment hold support is unavailable/);assert.equal(output.calls.length,0);assert.equal(output.downloads.length,0);
 }
});
