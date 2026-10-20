import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {pagesFor} from '../public/access.js';
import {esc} from '../public/domain.js';
const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
const renderSource=source.slice(source.indexOf('function render(){'),source.indexOf('const head='));
function workspace(role,page='settings'){
 const app={innerHTML:''},company={id:'c1',name:'Example School',role},switcher={};
 const views=Object.fromEntries(pagesFor(role).map(p=>[p,()=>'<h1>'+p+'</h1>']));
 const context=vm.createContext({app,company,companies:[company],page,views,pagesFor,esc,self:()=>null,navIcon:()=>'',btn:(label,action)=>'<button data-action="'+action+'">'+label+'</button>',$:selector=>selector==='#company-switch'?switcher:null});
 vm.runInContext(renderSource+';render();',context);return {html:app.innerHTML,switcher};
}
test('Top module banner preserves every role menu and puts navigation before workspace content',()=>{
 for(const role of ['admin','principal','president','accountant','hr','staff','manager','director']){
  const {html,switcher}=workspace(role),actual=[...html.matchAll(/data-page="([^"]+)"/g)].map(m=>m[1]);
  assert.deepEqual(actual,[...pagesFor(role)].sort((a,b)=>['overview','staff','attendance','leave','balances','leave_rules','holidays','payroll','letters','assessments','reports','settings'].indexOf(a)-['overview','staff','attendance','leave','balances','leave_rules','holidays','payroll','letters','assessments','reports','settings'].indexOf(b)));
  assert.equal((html.match(/aria-current="page"/g)||[]).length,1);assert.ok(html.includes('class="workspace-header"'));assert.ok(html.includes('class="nav module-nav"'));assert.ok(!html.includes('<aside'));assert.ok(!html.includes('sidebar-foot'));
  assert.ok(html.indexOf('id="company-switch"')<html.indexOf('<nav'));assert.ok(html.indexOf('</nav>')<html.indexOf('<main'));assert.equal(typeof switcher.onchange,'function');
 }
 const staff=workspace('staff').html;assert.ok(staff.includes('My payslips'));assert.ok(!staff.includes('data-page="settings"'));
});
