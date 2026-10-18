import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateStaffImport} from '../public/staff-master.js';
const base={code:'DED-CSV',name:'Deductions import QA',email:'ded-import@example.invalid',joining_date:'2026-10-01',basic:'20000'};
test('PT and Security Deposit CSV overrides retain explicit zero/false and blank defaults',()=>{const a=validateStaffImport([{...base,pt_override:'0',deposit_eligible_override:'false'}])[0];assert.equal(a.pt_override,'0');assert.equal(a.deposit_eligible_override,false);const b=validateStaffImport([base])[0];assert.equal(b.pt_override,'');assert.equal(b.deposit_eligible_override,null);});
test('Invalid monthly PT and deposit eligibility are rejected before upload',()=>{assert.throws(()=>validateStaffImport([{...base,pt_override:'-200'}]));assert.throws(()=>validateStaffImport([{...base,deposit_eligible_override:'maybe'}]));});
