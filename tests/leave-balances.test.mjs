import {test} from 'node:test';
import assert from 'node:assert/strict';
import {paidLeaveTypes,balanceEntry} from '../public/leave-balances.js';
test('Bulk balances use CL EL SL and all custom paid types, including inactive balances',()=>{const p=paidLeaveTypes([{code:'LWP',paid:false},{code:'SL',paid:true},{code:'PL',paid:true,active:false},{code:'CL',paid:true},{code:'EL',paid:true}]);assert.deepEqual(p.map(x=>x.code),['CL','EL','SL','PL']);});
test('Targets distinguish blank from explicit zero and retain the original balances',()=>{const row=balanceEntry({id:'s1',leave_balances:{CL:12,SL:4}},{CL:'0',EL:'2.5',SL:''});assert.deepEqual(row,{staff_id:'s1',balances:{CL:0,EL:2.5},expected_balances:{CL:12,EL:0}});});
test('Invalid targets and empty selected rows are rejected',()=>{for(const n of ['-1','0.25','10000','NaN','Infinity'])assert.throws(()=>balanceEntry({id:'s1'},{CL:n}));assert.throws(()=>balanceEntry({id:'s1'},{CL:' '}));assert.equal(balanceEntry({id:'s1'},{CL:'9999.5'}).balances.CL,9999.5);});
