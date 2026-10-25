import {test} from 'node:test';
import assert from 'node:assert/strict';
import {prepareLateReport,lateDrafts,reportTime,lateTemplateCSV} from '../public/late-csv.js';
import {allocateLateAllowance} from '../public/lateness.js';
import {attendanceDraft} from '../public/bulk-attendance.js';

const staff=[['2','S Samatha'],['4','Sujatha Mukherjee'],['12','Ketaki Chattopadhyay']].map(([id,name])=>({id,biometric_id:id,name,department:'Teaching',status:'active',joining_date:'2026-01-01',shift_start:'07:56:00',shift_end:'14:30:00'}));
const csv=`From Date,01-09-2026,To Date,30-09-2026,
,,,,
Log Date,Emp ID,Emp Name,Shift Start,LogTime
,,,,
11-Sep-26,2,S Samatha,7:56:00 AM,7:56:54 AM
16-Sep-26,2,S Samatha,7:56:00 AM,7:58:11 AM
17-Sep-26,2,S Samatha,7:56:00 AM,1:46:21 PM
05-Sep-26,4,Sujatha Mukherjee,7:56:00 AM,8:06:28 AM
07-Sep-26,4,Sujatha Mukherjee,7:56:00 AM,8:09:54 AM
08-Sep-26,4,Sujatha Mukherjee,7:56:00 AM,7:59:42 AM
10-Sep-26,4,Sujatha Mukherjee,7:56:00 AM,7:57:11 AM
21-Sep-26,12,Ketaki Chattopadhyay,7:56:00 AM,7:56:29 AM
24-Sep-26,12,Ketaki Chattopadhyay,7:56:00 AM,8:00:17 AM`;
const single='Log Date,Emp ID,Emp Name,Shift Start,LogTime\n11-Sep-26,2,S Samatha,7:56:00 AM,7:58:11 AM';

test('Exact supplied report supports date-range preamble, blank rows, seconds and PM',()=>{
 const rows=prepareLateReport('\uFEFF'+csv.replaceAll('\n','\r\n'),staff);
 assert.equal(rows.length,9);assert.deepEqual(rows.map(r=>r.late_minutes),[0,2,350,10,13,3,1,0,4]);
 assert.equal(rows[2].in_time,'13:46:21');assert.equal(rows[2].work_date,'2026-09-17');
 assert.equal(prepareLateReport(single,staff)[0].late_minutes,2);
 for(const date of ['11-09-2026','2026-09-11'])assert.equal(prepareLateReport(single.replace('11-Sep-26',date),staff)[0].work_date,'2026-09-11');
 assert.throws(()=>prepareLateReport(lateTemplateCSV(),staff),/1 to 1,000/);
 const sujatha=rows.filter(r=>r.staff_id==='4').map(r=>({...r,minutes:r.late_minutes,date:r.work_date}));
 const plan=allocateLateAllowance(sujatha);assert.equal(plan.total_minutes,27);assert.equal(plan.used_minutes,14);assert.equal(plan.uncovered_minutes,13);
});
test('Time parsing handles midnight/noon and rejects invalid hours, minutes and seconds',()=>{
 assert.equal(reportTime('12:00:01 AM').time,'00:00:01');assert.equal(reportTime('12:00:01 PM').time,'12:00:01');assert.equal(reportTime('23:59:59').seconds,86399);
 for(const value of ['0:00 AM','13:00 PM','24:00','07:60:00','07:56:60','7:5 AM','garbage'])assert.throws(()=>reportTime(value));
});
test('Bad ranges, identities, duplicates, shifts and employment reject the report',()=>{
 for(const text of [csv.replace('30-09-2026','01-09-2026'),csv.replace('01-09-2026','31-09-2026'),csv.replace('To Date','Other'),single.replace(',2,',',02,'),single.replace('S Samatha','Other'),single+'\n'+single.split('\n')[1],single.replace('7:58:11 AM','7:55:00 AM'),single.replace('Log Date','Date'),single+',unexpected'])assert.throws(()=>prepareLateReport(text,staff));
 for(const change of [{shift_start:'08:00:00'},{shift_end:'06:00:00'},{status:'separated'},{joining_date:'2026-10-01'},{leaving_date:'2026-09-01'}])assert.throws(()=>prepareLateReport(single,[{...staff[0],...change}]));
 assert.throws(()=>prepareLateReport(single,[staff[0],{...staff[0],id:'other'}]),/ambiguous/);
 assert.throws(()=>prepareLateReport('"unclosed',staff),/Unclosed/);
 assert.throws(()=>prepareLateReport('x'.repeat(2_000_001),staff),/2 MB/);
 assert.throws(()=>prepareLateReport(single.split('\n')[0]+'\n'+Array(1001).fill(single.split('\n')[1]).join('\n'),staff),/1,000/);
});
test('Staging preserves snapshots, out time with seconds and early minutes without inventing a departure',()=>{
 const report=prepareLateReport(csv,staff);
 const current={...attendanceDraft({staff_id:'2',source_hash:'v1',attendance:{status:'present',out_time:'14:25:39',early_minutes:5,note:'Reviewed'}}),staff:staff[0]};
 const draft=lateDrafts(report,[current],'Teaching','2026-09-17').get('2');
 assert.equal(draft.in_time,'13:46:21');assert.equal(draft.late_minutes,350);assert.equal(draft.out_time,'14:25:39');assert.equal(draft.early_minutes,5);assert.equal(draft.source_hash,'v1');assert.equal(draft.calculate_shift,false);assert.ok(draft.note.includes('07:56:00'));assert.equal(current.in_time,'');
 const fresh={...attendanceDraft({staff_id:'2',source_hash:'v2'}),staff:staff[0]};
 assert.equal(lateDrafts(report,[fresh],'Teaching','2026-09-17').get('2').out_time,'');
 for(const status of ['absent','half_day','holiday'])assert.throws(()=>lateDrafts(report,[{...current,status}],'Teaching','2026-09-17'),/manual review/);
 assert.throws(()=>lateDrafts(report,[{...current,staff:{shift_start:'08:00:00'}}],'Teaching','2026-09-17'),/shift/);
 assert.throws(()=>lateDrafts(report,[],'Teaching','2026-09-17'),/reload/);
 assert.throws(()=>lateDrafts(report,[current],'Other','2026-09-17'),/No report rows/);
 assert.throws(()=>lateDrafts(report,[{...current,note:'x'.repeat(500)}],'Teaching','2026-09-17'),/500/);
});
