import {test} from 'node:test';
import assert from 'node:assert/strict';
import {salaryTotals,salaryEarnings} from '../public/salary.js';
import {validateStaffImport} from '../public/staff-master.js';
test('Gross excludes HOD allowance; Cum Gross includes it exactly once',()=>{assert.deepEqual(salaryTotals({basic:20000,da:2000,hra:5000,cca:1000,other:1500,hod_allowance:2500}),{gross:29500,cum_gross:32000});});
test('Legacy salaries and decimal amounts preserve totals',()=>{assert.deepEqual(salaryTotals({basic:0.1,da:0.2}),{gross:0.3,cum_gross:0.3});assert.equal(salaryTotals({basic:100,other:20}).cum_gross,120);});
test('Payslip components keep the requested order without creating subtotal earnings',()=>{const rows=salaryEarnings({'HOD/Coordinator Allowances':5,CCA:4,HRA:3,DA:2,Basic:1,Allowances:6});assert.deepEqual(rows.map(([k])=>k),['Basic','DA','HRA','CCA','Allowances','HOD/Coordinator Allowances']);assert.equal(rows.reduce((n,[,v])=>n+v,0),21);});
test('Salary CSV accepts new components and rejects negative allowances',()=>{const r={code:'S1',name:'Sample',email:'sample@example.invalid',joining_date:'2026-10-01',basic:'20000',cca:'1000.25',hod_allowance:'2500'};assert.equal(validateStaffImport([r])[0].cca,1000.25);assert.throws(()=>validateStaffImport([{...r,hod_allowance:'-1'}]));});
