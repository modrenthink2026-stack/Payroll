import {config} from './config.js';
let session=JSON.parse(sessionStorage.getItem('payroll-session')||'null');
export const currentUser=()=>session?.user;
function save(s){session=s;sessionStorage.setItem('payroll-session',JSON.stringify(s));}
async function request(path,body,token){
  const res=await fetch(config.url+path,{method:'POST',headers:{apikey:config.key,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
  const data=await res.json().catch(()=>({message:'Unexpected server response'}));
  if(!res.ok)throw Error(data.msg||data.message||data.error_description||data.error||`Request failed (${res.status})`);
  return data;
}
export async function signIn(email,password){save(await request('/auth/v1/token?grant_type=password',{email,password}));}
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
export async function signOut(){try{if(session)await request('/auth/v1/logout',{},session.access_token);}finally{save(null);}}
async function refresh(){
  if(!session?.access_token)throw Error('Sign in to continue');
  const exp=JSON.parse(atob(session.access_token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).exp;
  if(exp<Date.now()/1000+60)save(await request('/auth/v1/token?grant_type=refresh_token',{refresh_token:session.refresh_token}));
}
export async function rpc(action,payload={}){
  await refresh();
  const request_id=payload.request_id||crypto.randomUUID();
  return request('/rest/v1/rpc/payroll_api',{action,payload:{...payload,request_id}},session.access_token);
}
