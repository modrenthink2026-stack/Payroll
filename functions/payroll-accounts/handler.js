const origins=new Set(['https://payroll-orpin-one.vercel.app','https://payroll-git-main-chandu-7362.vercel.app']);
export function createHandler({url,publicKey,adminKey,fetcher=fetch}){
 return async req=>{
  const origin=req.headers.get('origin');const headers={'Content-Type':'application/json','Cache-Control':'no-store',...(origins.has(origin)?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{})};
  const reply=(status,data)=>new Response(JSON.stringify(data),{status,headers});
  if(origin&&!origins.has(origin))return reply(403,{error:'Origin not allowed'});
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'}});
  if(req.method!=='POST')return reply(405,{error:'POST required'});
  const token=req.headers.get('authorization');if(!token?.startsWith('Bearer '))return reply(401,{error:'Sign in required'});
  const call=async(path,method,body,admin=false)=>{
   const res=await fetcher(url+path,{method,headers:{apikey:admin?adminKey:publicKey,Authorization:admin?'Bearer '+adminKey:token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
   const data=await res.json().catch(()=>({}));if(!res.ok)throw Error(admin?'Account service could not complete this operation':data.message||data.msg||'Access denied');return data;
  };
  try{
   const user=await call('/auth/v1/user','GET');if(!user.id)return reply(401,{error:'Sign in required'});
   const body=await req.json();const password=body.password;
   if(typeof password!=='string'||password.length<12)return reply(400,{error:'Use a temporary or new password of at least 12 characters'});
   if(body.action==='change_password'){
    if(!user.app_metadata?.payroll_password_change_required)return reply(400,{error:'No first-login password change pending'});
    if(user.app_metadata?.payroll_system_user_id)await call('/rest/v1/rpc/payroll_system_users','POST',{payload:{action:'password_ready'}});
    else await call('/rest/v1/rpc/payroll_api','POST',{action:'staff_password_ready',payload:{}});
    await call('/auth/v1/user','PUT',{password});
    await call('/auth/v1/admin/users/'+encodeURIComponent(user.id),'PUT',{app_metadata:{...user.app_metadata,payroll_password_change_required:false}},true);
    return reply(200,{password_changed:true,sign_in_again:true});
   }
   if(body.action==='create_system_user'){
    const payload={company_id:body.company_id,username:body.username,name:body.name,role:body.role};
    const plan=await call('/rest/v1/rpc/payroll_system_users','POST',{payload:{...payload,action:'prepare'}});
    if(plan.linked)return reply(200,{username:plan.username,status:'already_active'});
    const app_metadata={payroll_system_user_id:plan.id,payroll_company_id:body.company_id,payroll_password_change_required:true};
    const account=plan.pending_user_id?{id:plan.pending_user_id}:await call('/auth/v1/admin/users','POST',{email:plan.email,password,email_confirm:true,app_metadata},true);
    const user_id=account.id||account.user?.id;if(!user_id)throw Error('Account service returned no identity');
    await call('/rest/v1/rpc/payroll_system_users','POST',{payload:{action:'link',company_id:body.company_id,id:plan.id,user_id}});
    return reply(200,{username:plan.username,status:plan.pending_user_id?'resumed':'created'});
   }
   if(body.action!=='activate'||!Array.isArray(body.staff_ids)||body.staff_ids.length<1||body.staff_ids.length>25||typeof body.company_id!=='string')return reply(400,{error:'Choose 1–25 staff in one company'});
   const results=[];
   for(const staff_id of [...new Set(body.staff_ids)]){
    try{
     const payload={company_id:body.company_id,staff_id};
     // Authorization is checked by the role-checked RPC before using the admin Auth API.
     const plan=await call('/rest/v1/rpc/payroll_api','POST',{action:'staff_login_prepare',payload});
     if(plan.linked){results.push({staff_id,username:plan.username,status:'already_active'});continue;}
     const app_metadata={payroll_staff_id:staff_id,payroll_company_id:body.company_id,payroll_password_change_required:true};
     const account=plan.pending_user_id?
      {id:plan.pending_user_id}:
      await call('/auth/v1/admin/users','POST',{email:plan.email,password,email_confirm:true,app_metadata},true);
     const user_id=account.id||account.user?.id;if(!user_id)throw Error('Account service returned no identity');
     await call('/rest/v1/rpc/payroll_api','POST',{action:'staff_login_link',payload:{...payload,user_id}});
     results.push({staff_id,username:plan.username,status:'activated'});
    }catch(error){results.push({staff_id,status:'failed',message:error.message});}
   }
   return reply(200,{results});
  }catch{return reply(403,{error:'Account operation failed. Check your authorization and try again.'});}
 };
}
