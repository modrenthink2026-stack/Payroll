export const fullAccess=role=>['admin','principal','president'].includes(role);
export function pagesFor(role){
 if(fullAccess(role))return ['overview','staff','attendance','leave','payroll','letters','assessments','reports','settings'];
 if(role==='staff')return ['leave','balances','payroll','leave_rules','holidays'];
 if(role==='hr')return ['staff','attendance','leave','letters'];
 if(role==='accountant')return ['overview','staff','attendance','leave','payroll','reports'];
 return ['overview','staff','attendance','leave','assessments','reports'];
}
export function loginEmail(identifier){
 const text=String(identifier||'').trim().toLowerCase();if(text.includes('@'))return text;
 const username=text.replace(/[^a-z0-9]+/g,'.').replace(/^\.+|\.+$/g,'');
 if(!username||username.length>64)throw Error('Enter your assigned staff Login ID or email.');
 return username+'@staff.payroll.invalid';
}
