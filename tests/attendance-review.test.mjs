import {test} from 'node:test';
import assert from 'node:assert/strict';
import {attendanceDraft,attendanceIssues} from '../public/bulk-attendance.js';
import {prepareLateReport,lateDrafts,prepareEarlyReport,earlyDrafts} from '../public/late-csv.js';
import {absenceDrafts} from '../public/absence-csv.js';

const staff={id:'s1',biometric_id:'2',name:'S Samatha',department:'Teaching',status:'active',joining_date:'2026-01-01',shift_start:'07:56:00',shift_end:'14:20:00'};
const fresh={...attendanceDraft({staff_id:'s1',source_hash:'v1'}),staff};
const late=value=>prepareLateReport('Log Date,Emp ID,Emp Name,Shift Start,LogTime\n17-Sep-26,2,S Samatha,7:56:00 AM,'+value,[staff]);
const early=value=>prepareEarlyReport('Log Date,Emp ID,Emp Name,Shift End,LogTime\n17-Sep-26,2,S Samatha,2:20:00 PM,'+value,[staff]);
const stageLate=(report,row=fresh)=>lateDrafts(report,[row],'Teaching','2026-09-17').get('s1');
const stageEarly=(report,row=fresh)=>earlyDrafts(report,[row],'Teaching','2026-09-17').get('s1');

test('Single-punch late/early rows require a status decision and never invent the other time',()=>{
 const arrival=stageLate(late('7:58:11 AM'));
 assert.equal(arrival.status,'');assert.equal(arrival.in_time,'07:58:11');assert.equal(arrival.out_time,'');assert.equal(arrival.late_minutes,2);
 assert.deepEqual(attendanceIssues(arrival,staff),['Missing out punch']);
 const departure=stageEarly(early('2:17:31 PM'));
 assert.equal(departure.status,'');assert.equal(departure.in_time,'');assert.equal(departure.out_time,'14:17:31');assert.deepEqual(attendanceIssues(departure,staff),['Missing in punch']);
});
test('An empty LogTime flags missing evidence while retaining known reviewed times and minutes',()=>{
 const report=late('');assert.equal(report[0].in_time,'');assert.equal(report[0].late_minutes,null);
 const row={...fresh,in_time:'08:01:23',out_time:'14:20:00',late_minutes:5,early_minutes:0};
 const arrival=stageLate(report,row);assert.equal(arrival.status,'');assert.equal(arrival.in_time,row.in_time);assert.equal(arrival.late_minutes,5);assert.ok(arrival.note.includes('MISSING'));
 const departure=stageEarly(early(''),row);assert.equal(departure.status,'');assert.equal(departure.out_time,row.out_time);assert.equal(departure.early_minutes,0);assert.ok(departure.note.includes('MISSING'));
 assert.equal(stageLate(report).in_time,'');assert.equal(stageEarly(early('')).out_time,'');
});
test('Afternoon arrival needs review even with both punches; PM shifts do not count as morning-shift exceptions',()=>{
 const row={...fresh,out_time:'14:20:00'};
 const draft=stageLate(late('1:46:21 PM'),row);
 assert.equal(draft.status,'');assert.equal(draft.late_minutes,350);assert.equal(draft.in_time,'13:46:21');assert.ok(attendanceIssues(draft,staff).some(x=>x.includes('Afternoon arrival')));
 assert.equal(attendanceIssues({...draft,status:'half_day'},staff).some(x=>x.includes('Afternoon arrival')),true);
 assert.deepEqual(attendanceIssues({status:'present',in_time:'13:01:00',out_time:'20:00:00'},{shift_start:'13:00:00',shift_end:'20:00:00'}),[]);
 assert.deepEqual(attendanceIssues({status:'present',in_time:'07:56:00',out_time:'14:20:00'},staff),[]);
});
test('Morning departure, invalid order and missing times remain visible; absence is an explicit decision',()=>{
 const departure=stageEarly(early('7:52:03 AM'),{...fresh,in_time:'07:30:00'});
 assert.equal(departure.status,'');assert.ok(attendanceIssues(departure,staff).some(x=>x.includes('Morning departure')));
 assert.ok(attendanceIssues({status:'present',in_time:'13:46:00',out_time:'08:00:00'},staff).includes('Departure must be after arrival'));
 const absence=absenceDrafts([{staff_id:'s1',work_date:'2026-09-17',department:'Teaching',shift:'General'}],[fresh],'Teaching','2026-09-17').get('s1');
 assert.equal(absence.status,'');assert.equal(absence.in_time,'');assert.equal(absence.out_time,'');
 assert.deepEqual(attendanceIssues({...absence,status:'absent'},staff),[]);
});
test('Completing a pair does not silently approve a previously pending row',()=>{
 const arrival=stageLate(late('7:58:11 AM'));
 const completed=stageEarly(early('2:17:31 PM'),arrival);
 assert.equal(completed.status,'');assert.equal(completed.in_time,'07:58:11');assert.equal(completed.out_time,'14:17:31');assert.equal(completed.late_minutes,2);
 assert.deepEqual(attendanceIssues(completed,staff),[]);
});
