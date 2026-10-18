import {test} from 'node:test';
import assert from 'node:assert/strict';
import {shiftDepartments,shiftCandidates} from '../public/shift-assignment.js';
const rows=[{id:'a',name:'Sample A',code:'001',department:'Teaching',status:'active',employee_ref:'EMP-001'},{id:'b',name:'Sample B',department:'Support',status:'active'},{id:'c',name:'Sample C',department:'Teaching',status:'separated'},{id:'d',name:'Sample D',department:'',status:'active'}];
test('Department selection includes active departments and unassigned staff',()=>{assert.deepEqual(shiftDepartments(rows),['','Support','Teaching']);assert.deepEqual(shiftCandidates(rows,'Teaching').map(s=>s.id),['a']);assert.deepEqual(shiftCandidates(rows,'').map(s=>s.id),['d']);});
test('Staff selection searches names, codes and reference IDs without separated records',()=>{assert.equal(shiftCandidates(rows,null).length,3);assert.equal(shiftCandidates(rows,null,'emp-001')[0].id,'a');assert.equal(shiftCandidates(rows,'Support','Sample A').length,0);assert.equal(shiftCandidates(rows,null,'Sample C').length,0);});
