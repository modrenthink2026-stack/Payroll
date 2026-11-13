import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
export function secureOrigin(value){const u=new URL(value);if(u.protocol!=='https:'||u.username||u.password||u.origin!==value)throw Error('Use an exact HTTPS origin without credentials/path');return u.origin;}
export function replaceRequired(source,before,after){if(!source.includes(before))throw Error('Web source changed; mobile adapter needs review: '+before.slice(0,60));return source.replace(before,after);}
export function adaptPayroll(source,origin){
 secureOrigin(origin);
 source=replaceRequired(source,'export async function requestPasswordReset(email,appOrigin){','export async function requestPasswordReset(email,appOrigin){\n appOrigin='+JSON.stringify(origin)+';');
 return replaceRequired(source,'export async function acceptRecoveryLink(value,appOrigin){','export async function acceptRecoveryLink(value,appOrigin){\n appOrigin='+JSON.stringify(origin)+';');
}
export async function adaptProject(stage,origin){
 secureOrigin(origin);
 const edit=async(file,fn)=>{const p=join(stage,'src',file);await writeFile(p,fn(await readFile(p,'utf8')));};
 // The native origin has no Vercel proxy; keep the configured HTTPS backend.
 await edit('supabase-network.js',s=>{if(!s.includes('export function supabaseConnectionUrl('))throw Error('Connection helper changed');return '// Mobile bundles call the HTTPS backend directly; no website proxy exists here.\nexport function supabaseConnectionUrl(projectUrl) { return projectUrl }\n';});
 for(const file of ['password-recovery.jsx','signup-confirmation.jsx','company-registration.jsx'])await edit(file,s=>s.replaceAll('window.location.origin',JSON.stringify(origin)));
 await edit('App.jsx',s=>{
  const before="return <SupabaseAccess>{(access, logout, passwordSettings) => <PlatformRouter db={supabase()} workspace={workspaceId} account={access} onLogout={logout} onPassword={passwordSettings}>{platform=><WorkspaceApp key={access.user.id + ':' + workspaceId + ':' + access.membership.role+':'+Boolean(platform.demoMode)} platform={platform} cloudAccount={access} onLogout={logout} onPasswordSettings={passwordSettings}/>}</PlatformRouter>}</SupabaseAccess>";
  s=replaceRequired(s,before,"return <SupabaseAccess>{(access,logout,passwordSettings)=><NativeMasterPreview key={access.user.id} access={access} logout={logout} passwordSettings={passwordSettings}/>}</SupabaseAccess>");
  s=replaceRequired(s,'platform.demoMode?platform.demoCompanyId:undefined','platform.nativePreviewCompanyId||(platform.demoMode?platform.demoCompanyId:undefined)');
  s=replaceRequired(s,"...(!platform.demoMode?['companies']:[])","...(!platform.demoMode&&!platform.nativePreviewCompanyId?['companies']:[])");
  return s+`\nfunction NativeMasterPreview({access,logout,passwordSettings}){\n const [master,setMaster]=useState(''),[error,setError]=useState('');\n useEffect(()=>{let live=true;if(access.membership.role!=='owner'){setError('This mobile preview is for the master administrator only.');return;}supabase().from('pm_release_settings').select('master_company_id').eq('workspace_id',workspaceId).single().then(r=>{if(!live)return;if(r.error||!r.data?.master_company_id)setError('Master company could not be verified. Please use the web app.');else setMaster(r.data.master_company_id);}).catch(()=>{if(live)setError('Could not verify mobile preview access.');});return()=>{live=false;};},[access]);\n if(!master)return <main className="login-page"><section className="login-card"><h1>Project Manager mobile preview</h1><p role="status">{error||'Verifying master company…'}</p><button className="btn" onClick={logout}>Sign out</button></section></main>;\n return <WorkspaceApp platform={{nativePreviewCompanyId:master}} cloudAccount={access} onLogout={logout} onPasswordSettings={passwordSettings}/>;\n}\n`;
 });
 await edit('supabase-login.jsx',s=>{
  s=replaceRequired(s,'if (!access && register) return <RegisterCompany onCancel={()=>setRegister(false)} onContinue={()=>window.location.reload()}/>','if (!access && register) return <main className="login-page"><p>Company registration is available on the website. This mobile build is for master testing.</p><button onClick={()=>setRegister(false)}>Back to sign in</button></main>');
  return s.replace("!['/demo','/team'].includes(portal)&&<p className=\"login-register\"", "false&&<p className=\"login-register\"");
 });
}
