import {test} from 'node:test';
import assert from 'node:assert/strict';
import {prepareMonthlyReport,stageMonthlyReport,attendanceKey} from '../public/monthly-attendance.js';

const staff=[{id:'a',biometric_id:'001',code:'A',name:'Synthetic Teacher',department:'Teaching',shift_name:'Day',shift_start:'08:00:00',shift_end:'14:20:00',early_grace:3,status:'active',joining_date:'2026-01-01'},{id:'b',biometric_id:'002',code:'B',name:'Synthetic Office',department:'Office',shift_name:'Day',shift_start:'09:00:00',shift_end:'18:00:00',early_grace:0,status:'active',joining_date:'2026-01-01'}];
const absence='Date,Emp ID,Emp Name,Department,Shift\n01-Oct-26,001,Synthetic Teacher,Teaching,Day\n31-Oct-26,002,Synthetic Office,Office,Day';
const late='Log Date,Emp ID,Emp Name,Shift Start,LogTime\n01-Oct-26,001,Synthetic Teacher,8:00:00 AM,8:05:23 AM\n31-Oct-26,002,Synthetic Office,9:00:00 AM,9:02:11 AM';
const early='Log Date,Emp ID,Emp Name,Shift End,LogTime\n01-Oct-26,001,Synthetic Teacher,2:20:00 PM,2:17:31 PM\n31-Oct-26,002,Synthetic Office,6:00:00 PM,5:50:15 PM';
const snapshots=report=>report.map(row=>({staff_id:row.staff_id,work_date:row.work_date,source_hash:attendanceKey(row)+'v1',staff:staff.find(s=>s.id===row.staff_id),attendance:null}));

test('One monthly report stages every department and date with no group filtering',()=>{
 for(const kind of ['absence','late','early']){
  const report=prepareMonthlyReport(kind,{absence,late,early}[kind],staff,'2026-10');
  const rows=stageMonthlyReport(kind,report,snapshots(report));
  assert.equal(rows.length,2);assert.deepEqual(rows.map(r=>r.work_date),['2026-10-01','2026-10-31']);assert.deepEqual(new Set(rows.map(r=>r.staff.department)),new Set(['Teaching','Office']));assert.ok(rows.every(r=>r.selected&&r.status===''));
 }
});
test('Reports combine by employee/date while preserving unsaved review and the other punch',()=>{
 const arrival=prepareMonthlyReport('late',late,staff,'2026-10');
 let rows=stageMonthlyReport('late',arrival,snapshots(arrival));
 rows[0].status='present';rows[0].note+='; evidence reviewed';rows[1].selected=false;
 const departure=prepareMonthlyReport('early',early,staff,'2026-10');
 rows=stageMonthlyReport('early',departure,snapshots(departure),rows);
 assert.equal(rows.length,2);assert.equal(rows[0].in_time,'08:05:23');assert.equal(rows[0].out_time,'14:17:31');assert.equal(rows[0].late_minutes,5);assert.equal(rows[0].early_minutes,0);assert.equal(rows[0].status,'present');assert.ok(rows[0].note.includes('evidence reviewed'));
 assert.equal(rows[1].early_minutes,9);assert.equal(rows[1].in_time,'09:02:11');assert.equal(rows[1].selected,false);
});
test('Wrong month, unknown report type and changed or incomplete snapshots reject without altering prior drafts',()=>{
 for(const month of ['2026-09','2026-13','bad'])assert.throws(()=>prepareMonthlyReport('absence',absence,staff,month));
 assert.throws(()=>prepareMonthlyReport('other',absence,staff,'2026-10'));
 const report=prepareMonthlyReport('late',late,staff,'2026-10'),loaded=snapshots(report),rows=stageMonthlyReport('late',report,loaded),before=structuredClone(rows);
 assert.throws(()=>stageMonthlyReport('late',report,[{...loaded[0],source_hash:'changed'},loaded[1]],rows),/changed/);
 assert.throws(()=>stageMonthlyReport('late',report,[loaded[0]],rows),/changed/);
 assert.throws(()=>stageMonthlyReport('late',report,[{...loaded[0],staff:{...staff[0],department:'Other'}},loaded[1]],rows),/Department/);
 assert.deepEqual(rows,before);
});
test('A complete 500-person, 31-day CSV fits the 15,500-row preview limit',()=>{
 const people=Array.from({length:500},(_,i)=>({...staff[0],id:'staff-'+i,biometric_id:'bio-'+i,name:'Synthetic '+i,department:i%2?'Teaching':'Office'}));
 const csv='Date,Emp ID,Emp Name,Department,Shift\n'+people.flatMap(s=>Array.from({length:31},(_,d)=>`2026-10-${String(d+1).padStart(2,'0')},${s.biometric_id},${s.name},${s.department},Day`)).join('\n');
 assert.ok(Buffer.byteLength(csv)<2_000_000);
 const report=prepareMonthlyReport('absence',csv,people,'2026-10');assert.equal(report.length,15500);
 const loaded=report.map(r=>({staff_id:r.staff_id,work_date:r.work_date,source_hash:attendanceKey(r),staff:people[Number(r.staff_id.slice(6))],attendance:null}));
 const rows=stageMonthlyReport('absence',report,loaded);assert.equal(rows.length,15500);assert.equal(new Set(rows.map(attendanceKey)).size,15500);
});
