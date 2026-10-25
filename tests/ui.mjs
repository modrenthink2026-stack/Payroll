import {chromium} from 'playwright';
import {readFile,mkdir} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
import assert from 'node:assert/strict';

const browser=await chromium.launch({headless:true,...(process.env.PAYROLL_BROWSER_CHANNEL?{channel:process.env.PAYROLL_BROWSER_CHANNEL}:{})});
try{
 await mkdir('qa',{recursive:true});
 const user={id:'test-admin',email:'qa-admin@example.invalid'};
 const co={id:'test-company',name:'Northfield Industries',address:'Hyderabad, India',settings:{working_days:[1,2,3,4,5,6],holidays:[],pf_rate:12,pf_employer_rate:12,pf_cap:25000,esi_rate:.75,esi_employer_rate:3.25,statutory_reviewed:false,effective_from:'2026-10-01',deposit_enabled:false,deposit_cap:0}};
 const staff=[{id:'s1',code:'EMP-001',name:'Sample Staff A',login_name:'sample.staff.a',email:'staff-a@example.invalid',designation:'Site Engineer',department:'Engineering',joining_date:'2026-10-01',service_status:'probation',status:'active',leave_balances:{CL:12,SL:12,EL:0}},{id:'s2',code:'EMP-002',name:'Sample Staff B',email:'staff-b@example.invalid',designation:'HR Executive',department:'Human Resources',joining_date:'2026-10-01',service_status:'confirmed',status:'active',leave_balances:{CL:8,SL:10,EL:3}}];
 const fixture={staff,salaries:staff.map(s=>({staff_id:s.id,effective_from:'2026-10-01',basic:20000,da:2000,hra:5000,other:3000})),profiles:[],attendance:[],punches:[],policies:[{code:'CL',name:'Casual leave',paid:true,annual_entitlement:12}],leaves:[],documents:[],assessments:[],increments:[],runs:[],lines:[],deposits:[],audit:[],salary_holds:[]};
 let role='admin',paused=false,platformOwner=false;const calls=[],errors=[];
 const page=await browser.newPage({viewport:{width:1440,height:1050}});
 page.on('pageerror',e=>errors.push(e.message));
 const jwt=Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+3600})).toString('base64url');
 await page.addInitScript(session=>sessionStorage.setItem('payroll-session',JSON.stringify(session)),{access_token:`test.${jwt}.signature`,refresh_token:'synthetic-refresh',user});
 await page.route('https://payroll.test/**',async route=>{
  const path=new URL(route.request().url()).pathname;
  if(path.startsWith('/supabase/')){
   if(path.endsWith('/payroll_platform_admin'))return route.fulfill(platformOwner?{json:{companies:[{id:co.id,name:co.name,status:'active',modules:{},revision:0,staff:2,members:1}]}}:{status:403,json:{message:'Platform administrator access required'}});
   const {action,payload}=route.request().postDataJSON();calls.push({action,payload});
   return route.fulfill({json:action==='bootstrap'?{companies:[{...co,role,...(paused?{platform_status:'paused'}:{})}]}:action==='state'?fixture:{ok:true}});
  }
  const local=resolve('public',path==='/'?'index.html':'.'+path);
  return route.fulfill({body:await readFile(local),contentType:({'.js':'text/javascript','.css':'text/css','.html':'text/html'})[extname(local)]||'text/plain'});
 });
 await page.goto('https://payroll.test/');await page.getByRole('heading',{name:'Overview',exact:true}).waitFor().catch(async error=>{console.error(await page.locator('body').innerText(),errors);throw error;});
 await page.screenshot({path:'qa/dashboard-desktop.png',fullPage:true});
 for(const title of ['Staff master','Attendance','Leave & approvals','Payroll & payslips','Letters & service','Assessments','Reports','Company settings']){
  await page.locator('nav').getByRole('button',{name:title,exact:true}).click();assert.ok((await page.locator('main').innerText()).length>40);
 }
 await page.locator('nav').getByRole('button',{name:'Staff master',exact:true}).click();
 await page.getByRole('button',{name:'+ Add staff',exact:true}).click();
 await page.getByLabel('Staff code',{exact:true}).fill('QA003');await page.getByLabel('Full name').fill('UI Test Staff');
 await page.getByLabel('Joining date',{exact:true}).fill('2026-10-01');await page.getByRole('button',{name:'Save',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('#modal').open);
 assert.equal(calls.find(c=>c.action==='staff_save')?.payload.name,'UI Test Staff');
 await page.locator('nav').getByRole('button',{name:'Letters & service',exact:true}).click();
 await page.getByRole('button',{name:'+ Create letter',exact:true}).click();
 await page.getByLabel('Staff / candidate',{exact:true}).selectOption('s1');await page.getByLabel('Letter type',{exact:true}).selectOption('Experience letter');
 assert.equal(await page.getByLabel('Recipient name').inputValue(),'Sample Staff A');assert.ok((await page.getByLabel('Letter content').inputValue()).includes('This is to certify'));
 await page.getByRole('button',{name:'Cancel',exact:true}).click();
 await page.setViewportSize({width:390,height:844});await page.getByLabel('Go to module').selectOption('overview');
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'qa/dashboard-mobile.png',fullPage:true});
 await page.getByLabel('Go to module').selectOption('staff');await page.getByRole('heading',{name:'Staff master',exact:true}).waitFor();
 const table=page.locator('.staff-master-panel .table-wrap');await table.evaluate(element=>{element.scrollLeft=350;});
 const name=page.locator('.staff-master-panel tbody td').first();assert.ok(await name.isVisible());
 assert.ok((await name.boundingBox()).x>=0);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:'qa/staff-mobile.png',fullPage:true});
 await page.setViewportSize({width:320,height:700});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.emulateMedia({media:'print'});
 assert.equal(await page.locator('.staff-master-panel th').first().evaluate(element=>getComputedStyle(element).position),'static');
 assert.equal(await table.evaluate(element=>getComputedStyle(element).maxHeight),'none');
 await page.emulateMedia({media:'screen'});
 role='staff';await page.reload();await page.getByLabel('Go to module').waitFor();
 assert.equal(await page.locator('#mobile-page option').count(),5);assert.equal(await page.getByRole('button',{name:'Company settings',exact:true}).count(),0);
 paused=true;await page.reload();await page.getByText('Company workspace unavailable',{exact:true}).waitFor();assert.equal(await page.locator('#company-switch').count(),1);
 role='admin';paused=false;platformOwner=true;await page.setViewportSize({width:390,height:844});await page.reload();await page.getByRole('button',{name:'Platform Admin',exact:true}).click();
 assert.equal(await page.locator('[data-platform-module]:checked').count(),0);
 assert.deepEqual(errors,[]);
 console.log('PASS: eight module screens, real API-client requests with mocked backend, staff form, letter merge, mobile layout, five staff screens and paused-company rendering.');
}finally{await browser.close();}
