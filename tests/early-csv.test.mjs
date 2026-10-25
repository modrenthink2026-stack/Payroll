import {test} from 'node:test';
import assert from 'node:assert/strict';
import {prepareEarlyReport,earlyDrafts,earlyTemplateCSV,prepareLateReport,lateDrafts} from '../public/late-csv.js';
import {attendanceDraft} from '../public/bulk-attendance.js';

const staff=[['2','S Samatha'],['3','Reena Singh'],['4','Sujatha Mukherjee'],['14','G Sunitha'],['124','P. Haritha']].map(([id,name])=>({id,biometric_id:id,name,department:'Teaching',status:'active',joining_date:'2026-01-01',shift_start:'07:56:00',shift_end:'14:20:00',early_grace:0}));
const csv=`From Date,01-09-2026,To Date,30-09-2026,
,,,,
Log Date,Emp ID,Emp Name,Shift End,LogTime
,,,,
12-Sep-26,2,S Samatha,2:20:00 PM,2:17:31 PM
26-Sep-26,2,S Samatha,2:20:00 PM,12:57:36 PM
28-Sep-26,3,Reena Singh,2:20:00 PM,7:36:40 AM
05-Sep-26,4,Sujatha Mukherjee,2:20:00 PM,8:08:33 AM
07-Sep-26,4,Sujatha Mukherjee,2:20:00 PM,8:11:59 AM
22-Sep-26,4,Sujatha Mukherjee,2:20:00 PM,7:52:03 AM
30-Sep-26,4,Sujatha Mukherjee,2:20:00 PM,11:28:42 AM
07-Sep-26,14,G Sunitha,2:20:00 PM,12:56:02 PM
03-Sep-26,124,P. Haritha,2:20:00 PM,2:19:32 PM
07-Sep-26,124,P. Haritha,2:20:00 PM,2:18:57 PM`;
const single='Log Date,Emp ID,Emp Name,Shift End,LogTime\n12-Sep-26,2,S Samatha,2:20:00 PM,2:17:31 PM';
const current={...attendanceDraft({staff_id:'2',source_hash:'v1',attendance:{status:'present',in_time:'08:00:39',raw_late_minutes:4,note:'Reviewed'}}),staff:staff[0]};

test('Supplied early-going report parses metadata, blanks and AM/PM seconds with exact whole-minute totals',()=>{
 const rows=prepareEarlyReport('\uFEFF'+csv.replaceAll('\n','\r\n'),staff);
 assert.deepEqual(rows.map(r=>r.early_minutes),[2,82,403,371,368,387,171,83,0,1]);
 assert.deepEqual(staff.map(s=>rows.filter(r=>r.staff_id===s.id).reduce((n,r)=>n+r.early_minutes,0)),[84,403,1297,83,1]);
 assert.equal(rows[1].out_time,'12:57:36');assert.equal(rows[2].out_time,'07:36:40');
 assert.throws(()=>prepareEarlyReport(earlyTemplateCSV(),staff),/1 to 1,000/);
 for(const date of ['12-09-2026','2026-09-12'])assert.equal(prepareEarlyReport(single.replace('12-Sep-26',date),staff)[0].work_date,'2026-09-12');
});
test('Configured daily early grace is subtracted once, with a floor of zero',()=>{
 const adjusted=staff.map(s=>({...s,early_grace:3}));
 const rows=prepareEarlyReport(csv,adjusted);assert.equal(rows[0].early_minutes,0);assert.equal(rows[1].early_minutes,79);assert.equal(rows[9].early_minutes,0);
 const draft=earlyDrafts(rows,[current],'Teaching','2026-09-26').get('2');assert.equal(draft.early_minutes,79);assert.ok(draft.note.includes('grace 3 min'));
});
test('Report rejects unknown identities, mismatched shifts, bad ranges, duplicates and overnight ambiguity',()=>{
 for(const text of [single.replace(',2,',',002,'),single.replace('S Samatha','Other'),single.replace('2:20:00 PM','2:30:00 PM'),single.replace('2:17:31 PM','2:21:00 PM'),single.replace('2:17:31 PM','2:99:00 PM'),single.replace('Shift End','Shift Start'),single+'\n'+single.split('\n')[1],csv.replace('30-09-2026','01-09-2026')])assert.throws(()=>prepareEarlyReport(text,staff));
 for(const change of [{status:'separated'},{joining_date:'2026-10-01'},{leaving_date:'2026-09-01'},{shift_start:'22:00:00'}])assert.throws(()=>prepareEarlyReport(single,[{...staff[0],...change}]));
 assert.throws(()=>prepareEarlyReport(single,[staff[0],{...staff[0],id:'other'}]),/ambiguous/);
 assert.throws(()=>prepareEarlyReport('x'.repeat(2_000_001),staff),/2 MB/);
 assert.throws(()=>prepareEarlyReport(single.split('\n')[0]+'\n'+Array(1001).fill(single.split('\n')[1]).join('\n'),staff),/1,000/);
});
test('Early staging preserves arrival seconds, raw lateness and snapshot; invalid attendance cannot be overwritten',()=>{
 const rows=prepareEarlyReport(csv,staff),draft=earlyDrafts(rows,[current],'Teaching','2026-09-12').get('2');
 assert.equal(draft.in_time,'08:00:39');assert.equal(draft.late_minutes,4);assert.equal(draft.out_time,'14:17:31');assert.equal(draft.early_minutes,2);assert.equal(draft.source_hash,'v1');assert.equal(draft.calculate_shift,false);assert.equal(draft.out_next_day,false);assert.equal(current.out_time,'');
 assert.equal(earlyDrafts(rows,[draft],'Teaching','2026-09-12').get('2').note,draft.note);
 for(const change of [{status:'absent'},{status:'half_day'},{status:'holiday'},{out_next_day:true},{in_time:'14:18:00'},{in_time:'14:17:31'},{staff:{shift_end:'15:00:00'}},{note:'x'.repeat(500)}])assert.throws(()=>earlyDrafts(rows,[{...current,...change}],'Teaching','2026-09-12'));
 assert.throws(()=>earlyDrafts(rows,[],'Teaching','2026-09-12'),/reload/);assert.throws(()=>earlyDrafts(rows,[current],'Other','2026-09-12'),/No report rows/);
});
test('Late and early reports compose in either order without removing the other minutes or source notes',()=>{
 const early=prepareEarlyReport(single,staff),late=prepareLateReport('Log Date,Emp ID,Emp Name,Shift Start,LogTime\n12-Sep-26,2,S Samatha,7:56:00 AM,8:00:39 AM',staff);
 const applyEarly=draft=>earlyDrafts(early,[draft],'Teaching','2026-09-12').get('2');
 const applyLate=draft=>lateDrafts(late,[draft],'Teaching','2026-09-12').get('2');
 for(const draft of [applyEarly(applyLate(current)),applyLate(applyEarly(current))]){
  assert.equal(draft.in_time,'08:00:39');assert.equal(draft.out_time,'14:17:31');assert.equal(draft.late_minutes,4);assert.equal(draft.early_minutes,2);assert.ok(draft.note.includes('Biometric late report'));assert.ok(draft.note.includes('Biometric early report'));
 }
 assert.throws(()=>lateDrafts(late,[{...current,out_time:'07:59:00'}],'Teaching','2026-09-12'),/before the recorded departure/);
});
