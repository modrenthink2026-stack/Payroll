import {Capacitor} from '@capacitor/core';
import {App} from '@capacitor/app';
import {Filesystem,Directory} from '@capacitor/filesystem';
import {Share} from '@capacitor/share';
if(Capacitor.isNativePlatform()){
 const notice=document.createElement('div');notice.id='native-connectivity';notice.setAttribute('role','status');notice.textContent='Offline — connect to the internet before entering or saving records.';
 const connectivity=()=>{if(!navigator.onLine&&!notice.isConnected)document.body?.append(notice);if(navigator.onLine)notice.remove();};
 addEventListener('online',connectivity);addEventListener('offline',connectivity);addEventListener('DOMContentLoaded',connectivity);
 App.addListener('appStateChange',({isActive})=>{if(isActive){connectivity();window.dispatchEvent(new Event('focus'));}}).catch(()=>{});
 App.addListener('backButton',({canGoBack})=>{const dialog=document.querySelector('dialog[open]');if(dialog){dialog.close();return;}if(canGoBack){history.back();return;}if(confirm('Close the app? Make sure your latest changes have finished saving.'))void App.exitApp();}).catch(()=>{});
 const cleanup=async()=>{try{await Filesystem.rmdir({path:'exports',directory:Directory.Cache,recursive:true});}catch{}};
 const ready=cleanup();let exporting=false;
 async function exportFile(anchor){
  if(exporting)return;exporting=true;let path;
  try{
   // Start reading before the existing web code revokes its blob URL.
   const pending=fetch(anchor.href).then(r=>r.blob());await ready;const blob=await pending;
   if(blob.size>25*1024*1024)throw Error('This export is too large for the mobile share sheet. Use the web app.');
   const data=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).split(',')[1]);r.onerror=()=>reject(Error('Could not read export'));r.readAsDataURL(blob);});
   const filename=(anchor.download||'export').replace(/[^a-zA-Z0-9._-]/g,'_').slice(0,120);
   path=`exports/${Date.now()}-${filename}`;
   const saved=await Filesystem.writeFile({path,directory:Directory.Cache,data,recursive:true});
   await Share.share({title:filename,files:[saved.uri]});
  }catch(error){if(!/cancel/i.test(error?.message||''))alert('Could not share this export: '+(error?.message||'Please try again.'));}
  finally{if(path)try{await Filesystem.deleteFile({path,directory:Directory.Cache});}catch{}exporting=false;}
 }
 const isExport=a=>a?.download&&a.href.startsWith('blob:');
 const click=HTMLAnchorElement.prototype.click;
 HTMLAnchorElement.prototype.click=function(){if(isExport(this)){void exportFile(this);return;}return click.call(this);};
 document.addEventListener('click',e=>{const a=e.target.closest?.('a[download]');if(isExport(a)){e.preventDefault();void exportFile(a);}},true);
}
