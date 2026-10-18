import test from 'node:test';import assert from 'node:assert/strict';
import {fullAccess,pagesFor,loginEmail} from '../public/access.js';
test('Staff have exactly the five requested self-service screens',()=>{assert.deepEqual(pagesFor('staff'),['leave','balances','payroll','leave_rules','holidays']);assert.equal(fullAccess('staff'),false);});
test('HR has only staff entry, attendance/biometric leave, leave administration and letters',()=>{assert.deepEqual(pagesFor('hr'),['staff','attendance','leave','letters']);assert.equal(fullAccess('hr'),false);});
test('Principal, President and Administrator have every company module',()=>{for(const r of ['principal','president','admin']){assert.equal(fullAccess(r),true);assert.equal(pagesFor(r).length,9);assert.ok(pagesFor(r).includes('settings'));}});
test('Name Login IDs and existing emails use distinct compatible authentication paths',()=>{assert.equal(loginEmail(' Example Staff '),'example.staff@staff.payroll.invalid');assert.equal(loginEmail('example.staff.2'),'example.staff.2@staff.payroll.invalid');assert.equal(loginEmail(' Existing@Example.org '),'existing@example.org');assert.throws(()=>loginEmail(''));});
