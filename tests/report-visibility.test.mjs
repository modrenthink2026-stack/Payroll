import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {esc} from '../public/domain.js';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
const reports=source.slice(source.indexOf(' reports(){'),source.indexOf('\n settings(){'));
function render(modules,role='admin'){
 const ctx=vm.createContext({esc,company:{enabled_modules:modules,role},data:{runs:[]},month:'2026-10',hr:()=>['admin','hr'].includes(role),accountant:()=>['admin','accountant'].includes(role),head:(_a,_b,actions)=>actions,btn:(label,action)=>`<button data-action="${action}">${label}</button>`,paymentHoldsReady:()=>true,depositBalancesPanel:()=>'<section>DEPOSIT_BALANCES</section>'});
 return vm.runInContext('const view={'+reports+'};view.reports();',ctx);
}
const enabled={staff:true,attendance:true,leave:true,payroll:true,letters:true,assessments:true};
test('Payroll Demo reports hide disabled letters and assessments while retaining working modules',()=>{
 const html=render({...enabled,letters:false,assessments:false});
 for(const k of ['documents','assessments'])assert.ok(!html.includes(`data-action="report-${k}"`));
 for(const k of ['staff','attendance','leaves','deposits'])assert.ok(html.includes(`data-action="report-${k}"`));
 assert.ok(html.includes('Salary &amp; bank'));assert.ok(html.includes('raw-register'));assert.ok(html.includes('DEPOSIT_BALANCES'));
});
test('Company switches and re-enabling modules restore their reports',()=>{
 const off=render({...enabled,letters:false,assessments:false});const on=render(enabled);
 assert.ok(!off.includes('report-documents'));assert.ok(on.includes('report-documents'));assert.ok(on.includes('report-assessments'));
});
test('Disabled attendance and payroll remove their cross-module shortcuts and panels',()=>{
 const html=render({...enabled,attendance:false,payroll:false});
 for(const action of ['raw-register','late-month','salary-compare','salary-hold-report','report-attendance','report-deposits'])assert.ok(!html.includes(`data-action="${action}"`));
 assert.ok(!html.includes('Salary &amp; bank'));assert.ok(!html.includes('DEPOSIT_BALANCES'));assert.ok(html.includes('report-leaves'));
});
test('Legacy companies retain reports; managers do not see an HR-only biometric register action',()=>{
 const legacy=render(undefined);assert.ok(legacy.includes('report-documents'));assert.ok(legacy.includes('report-assessments'));
 const manager=render(enabled,'manager');assert.ok(!manager.includes('data-action="raw-register"'));assert.ok(manager.includes('data-action="late-month"'));assert.ok(!manager.includes('Salary &amp; bank'));
});
