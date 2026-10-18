import test from 'node:test';import assert from 'node:assert/strict';
import {allocateLateAllowance,minutesClock} from '../public/lateness.js';
const rows=values=>values.map((minutes,i)=>({attendance_id:String(i),date:'2026-11-'+String(i+1).padStart(2,'0'),minutes}));
test('user example: 2+3+10 covered, 30 retained as one half-day review incident',()=>{
 const p=allocateLateAllowance(rows([0,2,30,10,3]));assert.deepEqual(p.events.map(e=>e.minutes),[2,3,10,30]);assert.deepEqual(p.events.map(e=>e.covered),[true,true,true,false]);assert.equal(p.total_minutes,45);assert.equal(p.used_minutes,15);assert.equal(p.unused_minutes,10);assert.equal(p.net_excess_minutes,20);assert.equal(p.uncovered_minutes,30);
});
test('exact monthly boundary, repeated arrivals and deterministic equal-minute ordering',()=>{
 assert.equal(allocateLateAllowance(rows([25])).uncovered_minutes,0);assert.equal(allocateLateAllowance(rows([26])).used_minutes,0);
 const p=allocateLateAllowance(rows([10,10,10]));assert.equal(p.used_minutes,20);assert.equal(p.events.filter(e=>!e.covered).length,1);
 assert.equal(p.events[0].date,'2026-11-01');assert.equal(allocateLateAllowance(rows([15,10])).uncovered_minutes,0);
});
test('allowance starts afresh per employee/month and no inputs are mutated',()=>{
 const r=rows([30,2]);const before=structuredClone(r);allocateLateAllowance(r);assert.deepEqual(r,before);assert.equal(allocateLateAllowance(rows([25])).used_minutes,25);assert.equal(allocateLateAllowance([]).unused_minutes,25);
});
test('invalid late values are rejected',()=>{for(const v of [-1,1.5,NaN,Infinity])assert.throws(()=>allocateLateAllowance(rows([v])));});

test('late list shows in-time only for positive lateness and computes sorted cumulative minutes',()=>{
 const p=allocateLateAllowance([{attendance_id:'on-time',date:'2026-10-01',minutes:0,in_time:'08:00'},{attendance_id:'early',date:'2026-10-02',minutes:0,in_time:'07:58'},{attendance_id:'later',date:'2026-10-03',minutes:30,in_time:'08:30'},{attendance_id:'small',date:'2026-10-04',minutes:2,in_time:'08:02'}]);
 assert.deepEqual(p.events.map(e=>e.in_time),['08:02','08:30']);assert.deepEqual(p.events.map(e=>e.cumulative_minutes),[2,32]);assert.equal(minutesClock(117),'01:57');assert.equal(minutesClock(2),'00:02');
});
