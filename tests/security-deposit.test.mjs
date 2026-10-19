import {test} from 'node:test';
import assert from 'node:assert/strict';
import {securityDepositEstimate} from '../public/security-deposit.js';
test('Consolidated security deposit is 10% of its single amount',()=>{assert.equal(securityDepositEstimate({salary_mode:'consolidated',consolidated_amount:18000},{eligible:true,enabled:true,cap:10000}).amount,1800);});
test('Deposit preview observes eligibility, policy and remaining cap',()=>{const s={basic:20000};assert.equal(securityDepositEstimate(s,{eligible:true,enabled:true,cap:10000,balance:9500}).amount,500);assert.equal(securityDepositEstimate(s,{eligible:true,enabled:false,cap:10000}).note,'Company policy disabled');assert.equal(securityDepositEstimate(s,{eligible:false,enabled:true,cap:10000}).amount,0);assert.equal(securityDepositEstimate(s,{eligible:true,enabled:true,cap:10000,balance:11000}).amount,0);});

test('Consolidated HOD is included once in security deposit preview',()=>{assert.equal(securityDepositEstimate({salary_mode:'consolidated',consolidated_amount:18000,hod_allowance:3000},{eligible:true,enabled:true,cap:50000}).amount,2100);});
