import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {replaceRequired} from './web-adapter.mjs';
export async function adaptPayrollUI(www){
const file=join(www,'app.js');let s=await readFile(file,'utf8');
const start=s.indexOf(' app.innerHTML=`<div class="shell"><header class="workspace-header">',s.indexOf('function render()'));
const end=s.indexOf("\n $('#company-switch').onchange",start);
if(start<0||end<0)throw Error('Payroll render changed; review mobile UI adapter');
const replacement=" app.innerHTML=mobileWorkspace({navigation,page,companies,company,user:self()?.login_name||company.role,platform:typeof platform!=='undefined'&&platform,content:page?views[page]():empty('Company workspace unavailable','Contact the platform administrator to enable modules.')});";
s=s.slice(0,start)+replacement+s.slice(end);
s="import {mobileWorkspace} from './mobile-payroll-shell.js';\n"+s;
await writeFile(file,s);
await writeFile(join(www,'mobile-payroll-shell.js'),await readFile(new URL('./mobile-payroll-shell.js',import.meta.url),'utf8'));
}
