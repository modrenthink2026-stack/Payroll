import {salaryPayload} from './salary.js';
import {loginEmail} from './access.js';
import {config} from './config.js';
import {parseRecoveryLink} from './recovery.js';
let session=null;
try{session=JSON.parse(sessionStorage.getItem('payroll-session')||'null');}catch{sessionStorage.setItem('payroll-session','null');}
export const currentUser=()=>session?.user;
function save(s){session=s;sessionStorage.setItem('payroll-session',JSON.stringify(s));}
async function request(path,body,token){
  const res=await fetch(config.url+path,{method:'POST',headers:{apikey:config.key,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
  const data=await res.json().catch(()=>({message:'Unexpected server response'}));
  if(!res.ok)throw Error(data.msg||data.message||data.error_description||data.error||`Request failed (${res.status})`);
  return data;
}
export async function signIn(email,password){save(await request('/auth/v1/token?grant_type=password',{email:loginEmail(email),password}));sessionStorage.setItem('payroll-recovery','');}
export async function signUp(email,password){
  const r=await request('/auth/v1/signup',{email,password});
  if(r.access_token)save(r);
  return r;
}
export async function changePassword(password){
  await refresh();
  const res=await fetch(config.url+'/auth/v1/user',{method:'PUT',headers:{apikey:config.key,'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`},body:JSON.stringify({password})});
  const data=await res.json();if(!res.ok)throw Error(data.msg||data.message||'Password change failed');
}
export async function signOut(){try{if(session)await request('/auth/v1/logout',{},session.access_token);}finally{save(null);sessionStorage.setItem('payroll-recovery','');}}
export const recoveryActive=()=>!!session?.access_token&&sessionStorage.getItem('payroll-recovery')==='1';
export async function requestPasswordReset(email,appOrigin){
 const address=email.trim().toLowerCase();
 if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(address))throw Error('Enter your account email address.');
 const sent=Number(sessionStorage.getItem('payroll-reset-sent-at')||0);
 if(Date.now()-sent<60000)throw Error('Please wait one minute before requesting another reset email.');
 const origin=new URL(appOrigin).origin;
 if(!origin.startsWith('https://')&&!origin.startsWith('http://localhost'))throw Error('Use the secure deployed Payroll website.');
 await request('/auth/v1/recover?redirect_to='+encodeURIComponent(origin+'/?recovery=1'),{email:address});
 sessionStorage.setItem('payroll-reset-sent-at',String(Date.now()));
}
export async function acceptRecoveryLink(value,appOrigin){
 const link=parseRecoveryLink(value,appOrigin);
 const next=link.type==='hash'?await request('/auth/v1/verify',{token_hash:link.token_hash,type:'recovery'}):link;
 if(!next.access_token||!next.refresh_token)throw Error('Recovery session is missing. Request a new reset email.');
 // The Auth service, rather than client-side JWT claims, validates the recovery session.
 const res=await fetch(config.url+'/auth/v1/user',{headers:{apikey:config.key,Authorization:`Bearer ${next.access_token}`}});
 const user=await res.json();
 if(!res.ok||!user.id)throw Error('This recovery session is invalid or expired. Request a new reset email.');
 save({...next,user});sessionStorage.setItem('payroll-recovery','1');
}
async function refresh(){
  if(!session?.access_token)throw Error('Sign in to continue');
  const exp=JSON.parse(atob(session.access_token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).exp;
  if(exp<Date.now()/1000+60)save(await request('/auth/v1/token?grant_type=refresh_token',{refresh_token:session.refresh_token}));
}
export async function rpc(action,payload={}){
  if(['staff_save','initial_salary','increment_save'].includes(action))payload=salaryPayload(payload);
  await refresh();
  const request_id=payload.request_id||crypto.randomUUID();
  return request('/rest/v1/rpc/payroll_api',{action,payload:{...payload,request_id}},session.access_token);
}

export async function saveBulkLeaveBalances(payload){await refresh();return request('/rest/v1/rpc/payroll_bulk_leave_balances',{payload},session.access_token);}

export async function bulkAttendance(payload){await refresh();return request('/rest/v1/rpc/payroll_bulk_attendance',{payload},session.access_token);}
export async function monthlyAttendance(payload){await refresh();return request('/rest/v1/rpc/payroll_monthly_attendance',{payload},session.access_token);}
export async function accountAction(payload){await refresh();return request("/functions/v1/payroll-accounts",payload,session.access_token);}

export async function assignShifts(payload){await refresh();return request('/rest/v1/rpc/payroll_assign_shifts',{payload},session.access_token);}

export async function saveDepartmentSalaries(payload){payload={...payload,rows:payload.rows.map(salaryPayload)};await refresh();return request('/rest/v1/rpc/payroll_department_salaries',{payload},session.access_token);}

export async function assignUsernameRole(payload){await refresh();return request('/rest/v1/rpc/payroll_username_role',{payload},session.access_token);}

export async function systemUsers(payload){await refresh();return request('/rest/v1/rpc/payroll_system_users',{payload},session.access_token);}
export async function platformAdmin(payload){await refresh();return request('/rest/v1/rpc/payroll_platform_admin',{payload},session.access_token);}
