import {checkWorkspace} from './workspace-ui-check.mjs';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {resolve,extname,join} from 'node:path';
import {chromium} from 'playwright';
import {build} from 'esbuild';
import assert from 'node:assert/strict';
const root=resolve('www'),qa=resolve('qa');await mkdir(qa,{recursive:true});
const server=createServer(async(req,res)=>{try{const path=resolve(root,'.'+new URL(req.url,'http://local').pathname);if(path!==root&&!path.startsWith(root+'/'))throw Error('Invalid path');const file=path===root?join(root,'index.html'):path;const data=await readFile(file);res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png'})[extname(file)]||'application/octet-stream');res.end(data);}catch{res.writeHead(404).end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{}),headless:true,args:['--no-sandbox']});
try{
 for(const viewport of [{width:320,height:740},{width:390,height:844},{width:1024,height:768}]){
  const page=await browser.newPage({viewport});const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>{if(new URL(route.request().url()).hostname==='127.0.0.1')return route.continue();return route.abort();});
  await page.goto(`http://127.0.0.1:${server.address().port}/`);await page.locator('input').first().waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,'Login page should fit viewport');
  assert.deepEqual(errors,[]);await page.screenshot({path:join(qa,`login-${viewport.width}.png`),fullPage:true});
  await page.close();
 }
 await checkWorkspace(browser,`http://127.0.0.1:${server.address().port}`,qa);
 const mocks={
  '@capacitor/core':"export const Capacitor={isNativePlatform:()=>true};export const CapacitorHttp={request:async()=>{throw Error('Unexpected account network call in synthetic UI check')}}",
  '@capacitor/app':"export const App={addListener:async(name,fn)=>{(window.__nativeListeners??={})[name]=fn},exitApp:async()=>{window.__exit=true}}",
  '@capacitor/filesystem':"export const Directory={Cache:'CACHE'}; export const Filesystem={rmdir:async()=>{},writeFile:async(o)=>{window.__written=o;return {uri:'file:///cache/'+o.path}},deleteFile:async(o)=>{window.__deleted=o}}",
  '@capacitor/share':"export const Share={share:async(o)=>{window.__shared=o}}"
 };
 const bundle=await build({entryPoints:['native-shell.js'],bundle:true,write:false,format:'iife',plugins:[{name:'native-test-mocks',setup(b){b.onResolve({filter:/^@capacitor\//},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:mocks[a.path],loader:'js'}));}}]});
 const page=await browser.newPage();await page.route('**/*',route=>new URL(route.request().url()).hostname==='127.0.0.1'?route.continue():route.abort());await page.goto(`http://127.0.0.1:${server.address().port}/`);await page.evaluate(bundle.outputFiles[0].text);
 await page.evaluate(()=>{const a=document.createElement('a');a.download='../salary.csv';a.href=URL.createObjectURL(new Blob(['synthetic,123'],{type:'text/csv'}));a.click();URL.revokeObjectURL(a.href);});
 await page.waitForFunction(()=>window.__shared&&window.__deleted);
 const actual=await page.evaluate(()=>({written:window.__written,shared:window.__shared,deleted:window.__deleted}));
 assert.equal(Buffer.from(actual.written.data,'base64').toString(),'synthetic,123');assert.equal(actual.written.directory,'CACHE');assert.match(actual.written.path,/exports\/\d+-\.\._salary.csv/);assert.equal(actual.deleted.path,actual.written.path);assert.equal(actual.shared.files.length,1);
 await page.evaluate(()=>{const d=document.createElement('dialog');document.body.append(d);d.showModal();window.__nativeListeners.backButton({canGoBack:false});});
 assert.equal(await page.locator('dialog[open]').count(),0);assert.equal(await page.evaluate(()=>Boolean(window.__exit)),false);
 console.log('PASS: phone and iPad login layouts, no browser runtime errors, native export/share/cache cleanup and Android dialog-back handling. All data synthetic; external requests blocked.');
}finally{await browser.close();await new Promise(r=>server.close(r));}
