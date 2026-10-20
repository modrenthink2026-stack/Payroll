import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../public/app.js',import.meta.url),'utf8');
const css=readFileSync(new URL('../public/style.css',import.meta.url),'utf8');
function themeRuntime(saved,{blocked=false}={}){
 const values=new Map(saved?[['payroll-colour-theme',saved]]:[]),root={dataset:{}};
 const context=vm.createContext({document:{documentElement:root},localStorage:{getItem:k=>{if(blocked)throw Error('Storage unavailable');return values.get(k)},setItem:(k,v)=>{if(blocked)throw Error('Storage unavailable');values.set(k,v)}}});
 const begin=source.indexOf('const colourThemes='),end=source.indexOf('function toast(text)',begin);
 vm.runInContext(source.slice(begin,end)+';globalThis.themeAPI={applyColourTheme,themes:colourThemes};',context);
 return {root,values,api:context.themeAPI};
}
test('Appearance restores supported colours, persists choices and rejects unknown saved values',()=>{
 const runtime=themeRuntime('ocean');assert.equal(runtime.root.dataset.theme,'ocean');
 assert.equal(runtime.api.themes.length,5);
 for(const [key] of runtime.api.themes){runtime.api.applyColourTheme(key);assert.equal(runtime.root.dataset.theme,key);assert.equal(runtime.values.get('payroll-colour-theme'),key);}
 assert.equal(themeRuntime('untrusted-value').root.dataset.theme,'indigo');
});
test('Unavailable preference storage never blocks application startup or colour changes',()=>{
 const {root,api}=themeRuntime(null,{blocked:true});assert.equal(root.dataset.theme,'indigo');assert.doesNotThrow(()=>api.applyColourTheme('plum'));assert.equal(root.dataset.theme,'plum');
});
function luminance(hex){const c=hex.replace('#','').match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2]}
function contrast(a,b){const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)}
test('All five palettes keep primary button labels and sidebar text readable',()=>{
 const palettes=[...css.matchAll(/:root(?:\[data-theme=(\w+)\])?\{([^}]+)\}/g)].filter(m=>m[2].includes('--accent:'));assert.equal(palettes.length,5);
 const base=Object.fromEntries([...palettes[0][2].matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/g)].map(m=>[m[1],m[2]]));
 for(const match of palettes){const vars={...base,...Object.fromEntries([...match[2].matchAll(/--([\w-]+):\s*(#[0-9a-f]{6})/g)].map(m=>[m[1],m[2]]))};
  for(const key of ['accent','accent-hover'])assert.ok(contrast(vars[key],'#ffffff')>=4.5,match[1]+' '+key);
  assert.ok(contrast(vars['sidebar-text'],vars.sidebar)>=4.5,match[1]+' sidebar');assert.ok(contrast(vars.muted,'#ffffff')>=4.5);
 }
});
