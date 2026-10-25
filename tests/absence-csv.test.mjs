import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseCSV} from '../public/domain.js';
import {absenceDate,absenceTemplateCSV,prepareAbsenceReport,absenceDrafts} from '../public/absence-csv.js';

const staff=[{id:'s1',biometric_id:'1',code:'OTHER',name:'T R UDAYA KUMARI',department:'Pre Primary',shift_name:'General-1',status:'active',joining_date:'2026-01-01'}];
const csv='Date,Emp ID,Emp Name,Department,Shift\r\n,,,,\r\n04-Sep-26,1,T R UDAYA KUMARI,Pre Primary,General-1\r\n';
const source=parseCSV(csv);
test('Provided absence format ignores blank rows and resolves exact biometric ID',()=>{
 assert.deepEqual(prepareAbsenceReport(source,staff),[{staff_id:'s1',work_date:'2026-09-04',department:'Pre Primary',shift:'General-1'}]);
 assert.deepEqual(parseCSV(absenceTemplateCSV()),[]);
 assert.equal(absenceDate('29-Feb-24'),'2024-02-29');assert.equal(absenceDate('2026-09-04'),'2026-09-04');
 for(const value of ['31-Sep-26','29-Feb-26','04-Xxx-26','09/04/26','2026-13-01'])assert.throws(()=>absenceDate(value),/valid date/);
});
test('Unknown, ambiguous and mismatched identities, shifts and employment are rejected',()=>{
 for(const change of [{'Emp ID':'OTHER'},{'Emp ID':'01'},{'Emp Name':'Someone Else'},{Department:'Other'},{Shift:'Night'},{Shift:''}])assert.throws(()=>prepareAbsenceReport([{...source[0],...change}],staff));
 assert.throws(()=>prepareAbsenceReport(source,[...staff,{...staff[0],id:'s2'}]),/ambiguous/);
 for(const change of [{status:'separated'},{joining_date:'2026-10-01'},{leaving_date:'2026-09-03'}])assert.throws(()=>prepareAbsenceReport(source,[{...staff[0],...change}]),/inactive|employment/);
 assert.throws(()=>prepareAbsenceReport([...source,...source],staff),/Duplicate/);
 assert.throws(()=>prepareAbsenceReport([],staff));assert.throws(()=>prepareAbsenceReport(Array(15501).fill(source[0]),staff));
});
test('Leading zero IDs and normalized names survive without numeric coercion',()=>{
 const rows=[{...source[0],'Emp ID':'001','Emp Name':'t  r udaya kumari'}];
 assert.equal(prepareAbsenceReport(rows,[{...staff[0],biometric_id:'001'}])[0].staff_id,'s1');
 assert.throws(()=>prepareAbsenceReport(rows,staff),/Unknown/);
});
test('Only loaded department/date is staged; snapshots and existing notes survive',()=>{
 const report=prepareAbsenceReport([...source,{...source[0],Date:'05-Sep-26'}],staff);
 const current={staff_id:'s1',source_hash:'snapshot',status:'present',in_time:'09:05',out_time:'18:00',late_minutes:5,early_minutes:1,note:'Prior review'};
 const drafts=absenceDrafts(report,[current,{staff_id:'untouched'}],'Pre Primary','2026-09-04');
 assert.equal(drafts.size,1);
 assert.deepEqual(drafts.get('s1'),{...current,status:'',in_time:'',out_time:'',late_minutes:0,early_minutes:0,calculate_shift:false,out_next_day:false,note:'Prior review · Biometric absence report: General-1'});
 assert.equal(current.status,'present');assert.equal(current.in_time,'09:05');
 assert.throws(()=>absenceDrafts(report,[],'Pre Primary','2026-09-04'),/reload/);
 assert.throws(()=>absenceDrafts(report,[current],'Other','2026-09-04'),/No report rows/);
 assert.throws(()=>absenceDrafts(report,[{...current,note:'a'.repeat(500)}],'Pre Primary','2026-09-04'),/500/);
});
