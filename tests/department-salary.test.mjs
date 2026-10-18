import {test} from 'node:test';
import assert from 'node:assert/strict';
import {departmentSalaryRows} from '../public/department-salary.js';
test('Department salary rows include active staff with and without salary and the latest baseline',()=>{const staff=[{id:'a',status:'active',department:'Teaching'},{id:'b',status:'active',department:'Teaching'},{id:'c',status:'separated',department:'Teaching'},{id:'d',status:'active',department:'Support'}],salaries=[{id:'old',staff_id:'a',effective_from:'2026-01-01'},{id:'new',staff_id:'a',effective_from:'2026-10-01'}];const rows=departmentSalaryRows(staff,salaries,'Teaching');assert.deepEqual(rows.map(r=>r.staff.id),['a','b']);assert.equal(rows[0].salary.id,'new');assert.equal(rows[1].salary,null);assert.equal(salaries[0].id,'old');});
