import test from 'node:test';
import assert from 'node:assert/strict';
import {esc,parseCSV,csvText,weightedScore,letterBody,letterTypes} from '../public/domain.js';
test('CSV import supports quoted commas, escaped quotes and CRLF',()=>{
 assert.deepEqual(parseCSV('name,note\r\n"Ravi, K","a ""quote"""\r\n'),[{name:'Ravi, K',note:'a "quote"'}]);
});
test('malformed CSV is rejected before any import',()=>{
 for(const t of ['a,a\n1,2','a,b\n1','a,b\n"unterminated,1'])assert.throws(()=>parseCSV(t));
});
test('CSV exports neutralize spreadsheet formula injection',()=>{
 const text=csvText([{name:'=HYPERLINK("bad")',amount:100}]);
 assert.ok(text.includes("'=HYPERLINK"));
});
test('user supplied HTML is escaped in letters and screens',()=>{
 assert.equal(esc('<script>"&\''),'&lt;script&gt;&quot;&amp;&#39;');
});
test('weighted assessment validates scale and weight sum',()=>{
 assert.equal(weightedScore([{weight:60,rating:5},{weight:40,rating:3}]),4.2);
 assert.throws(()=>weightedScore([{weight:90,rating:5}]));
 assert.throws(()=>weightedScore([{weight:100,rating:6}]));
});
test('all requested letter types are available; templates remain unissued drafts',()=>{
 for(const t of ['Offer letter','Appointment letter','Service confirmation','Increment letter','Termination letter','Relieving letter','Experience letter']){
  assert.ok(letterTypes.includes(t));
  assert.ok(letterBody(t,{name:'Example',designation:'Engineer'},{name:'Test Company'}).includes('['));
 }
});
