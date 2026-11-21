import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,cp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {secureOrigin,adaptPayroll,replaceRequired,adaptProject} from '../web-adapter.mjs';
const app=JSON.parse(await readFile(new URL('../app.json',import.meta.url)));
test('native config bundles assets and does not permit remote navigation or cleartext',async()=>{
 const config=JSON.parse(await readFile(new URL('../capacitor.config.json',import.meta.url)));
 assert.equal(config.webDir,'www');assert.equal(config.appId,app.appId);assert.equal(config.server.url,undefined);assert.equal(config.server.allowNavigation,undefined);assert.equal(config.android.allowMixedContent,false);assert.equal(config.ios.webContentsDebuggingEnabled,false);
});
test('recovery accepts only explicit HTTPS origins and adapters stop on source drift',()=>{
 for(const u of ['http://example.com','https://example.com/path','https://u:p@example.com','https://example.com/'])assert.throws(()=>secureOrigin(u));
 assert.equal(secureOrigin('https://example.com'),'https://example.com');
 assert.throws(()=>adaptPayroll('',app.webOrigin));assert.throws(()=>replaceRequired('x','y','z'));
 const api=adaptPayroll('export async function requestPasswordReset(email,appOrigin){\n}\nexport async function acceptRecoveryLink(value,appOrigin){\n}',app.webOrigin);
 assert.equal(api.split('appOrigin='+JSON.stringify(app.webOrigin)).length-1,2);
});
test('Android backup/cleartext disabled and iOS supports iPhone and iPad',async()=>{
 const xml=await readFile(new URL('../android/app/src/main/AndroidManifest.xml',import.meta.url),'utf8');assert.match(xml,/android:allowBackup="false"/);assert.match(xml,/android:usesCleartextTraffic="false"/);assert.doesNotMatch(xml,/READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|CAMERA|ACCESS_FINE_LOCATION/);
 const pbx=await readFile(new URL('../ios/App/App.xcodeproj/project.pbxproj',import.meta.url),'utf8');assert.match(pbx,/TARGETED_DEVICE_FAMILY = "1,2"/);
 const privacy=await readFile(new URL('../ios/App/App/PrivacyInfo.xcprivacy',import.meta.url),'utf8');assert.match(privacy,/C617.1/);assert.match(pbx,/PrivacyInfo.xcprivacy in Resources/);
});
test('bundled HTML has mobile shell and contains no website-only API route',async()=>{
 const html=await readFile(new URL('../www/index.html',import.meta.url),'utf8');assert.match(html,/viewport-fit=cover/);assert.match(html,/native-shell.js/);assert.match(html,/mobile.css/);assert.match(html,/Content-Security-Policy/);assert.match(html,/script-src 'self';/);assert.match(html,/connect-src 'self' blob: https:\/\/uvowltyjnzqtozygalhf.supabase.co;/);
 if(app.kind==='payroll'){const c=await readFile(new URL('../www/config.js',import.meta.url),'utf8');assert.match(c,/https:\/\/uvowltyjnzqtozygalhf.supabase.co/);assert.doesNotMatch(c,/url: '\/supabase'/);}
});
test('Project Manager mobile preview resolves master from settings and reuses the fixed-company write boundary',{skip:app.kind!=='project'},async()=>{
 const temp=await mkdtemp(join(tmpdir(),'pm-mobile-adapter-'));
 try{
  await cp(new URL('../../src',import.meta.url),join(temp,'src'),{recursive:true});await adaptProject(temp,app.webOrigin);
  const s=await readFile(join(temp,'src/App.jsx'),'utf8');assert.match(s,/pm_release_settings/);assert.match(s,/nativePreviewCompanyId\|\|\(platform.demoMode/);assert.match(s,/membership.role!=='owner'/);assert.doesNotMatch(s,/=> <PlatformRouter/);
  const cloud=await readFile(join(temp,'src/company-cloud.js'),'utf8');assert.match(cloud,/query=query.eq\('id',fixedCompanyId\)/);assert.match(cloud,/fixedCompanyId&&company.id!==fixedCompanyId/);assert.match(cloud,/fixedCompanyId && companyId !== fixedCompanyId/);
 }finally{await rm(temp,{recursive:true,force:true});}
});
