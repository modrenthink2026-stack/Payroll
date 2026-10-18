import {test} from 'node:test';
import assert from 'node:assert/strict';
import {usernameOptions} from '../public/usernames.js';
test('User addition uses distinct usernames and references without email addresses',()=>{const rows=[{name:'Same Name',login_name:'same.name',code:'01',user_id:'a',status:'active',email:'private@example.invalid'},{name:'Same Name',login_name:'same.name.2',code:'02',user_id:'b',status:'active'},{name:'Pending',login_name:'pending',status:'active'},{name:'Left',login_name:'left',user_id:'c',status:'separated'}];const opts=usernameOptions(rows);assert.equal(opts.length,2);assert.equal(opts[0][0],'same.name');assert.equal(opts[1][0],'same.name.2');assert.equal(JSON.stringify(opts).includes('@'),false);});
