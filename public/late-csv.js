import {parseCSVRows} from './domain.js';
import {absenceDate} from './absence-csv.js';
import {attendanceIssues} from './bulk-attendance.js';

export const lateColumns=['Log Date','Emp ID','Emp Name','Shift Start','LogTime'];
export const lateTemplateCSV=()=>lateColumns.join(',')+'\r\n';
export const earlyColumns=['Log Date','Emp ID','Emp Name','Shift End','LogTime'];
export const earlyTemplateCSV=()=>earlyColumns.join(',')+'\r\n';
const normalized=value=>String(value??'').trim().replace(/\s+/g,' ').toLowerCase();
const reportDate=value=>absenceDate(value.replace(/^(\d{2})-(\d{2})-(\d{4})$/,'$3-$2-$1'));

export function reportTime(value){
 const match=/^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i.exec(String(value).trim());
 if(!match)throw Error('Use a valid time such as 7:56:54 AM or 07:56:54');
 let hour=Number(match[1]);const minute=Number(match[2]),second=Number(match[3]||0),period=match[4]?.toUpperCase();
 if(minute>59||second>59||hour>(period?12:23)||period&&hour<1)throw Error('Invalid report time');
 if(period)hour=hour%12+(period==='PM'?12:0);
 return {time:[hour,minute,second].map(n=>String(n).padStart(2,'0')).join(':'),seconds:hour*3600+minute*60+second};
}

export function prepareLateReport(text,staff){
 return prepareTimeReport(text,staff,false);
}
export function prepareEarlyReport(text,staff){
 return prepareTimeReport(text,staff,true);
}
function prepareTimeReport(text,staff,early){
 const columns=early?earlyColumns:lateColumns,label=early?'Early':'Late',shiftField=early?'shift_end':'shift_start';
 const records=parseCSVRows(text).map(row=>row.map(value=>value.trim().replace(/^\uFEFF/,'')));
 let from,to;
 if(records[0][0]==='From Date'){
  const range=records.shift();
  if(range[2]!=='To Date'||range.slice(4).some(Boolean))throw Error('Expected From Date, date, To Date, date');
  from=reportDate(range[1]||'');to=reportDate(range[3]||'');
  if(from>to)throw Error('From Date must not be after To Date');
 }
 const headers=records.shift();
 if(!headers||headers.length!==columns.length||headers.some((h,i)=>h!==columns[i]))throw Error('Use headings: '+columns.join(', '));
 if(!records.length||records.length>1000)throw Error('Upload 1 to 1,000 '+(early?'early-going':'late-coming')+' rows');
 const seen=new Set();
 return records.map((r,i)=>{
  const fail=message=>{throw Error(`${label} report row ${i+1}: ${message}`);};
  if(r.length!==columns.length||r.slice(0,4).some(v=>!v))fail('Expected five columns with employee, date and shift');
  const [dateValue,id,name,startValue,inValue]=r,date=reportDate(dateValue);
  if(from&&(date<from||date>to))fail('Log Date is outside the report date range');
  const matches=staff.filter(s=>s.biometric_id===id);
  if(matches.length!==1)fail('Unknown or ambiguous biometric Emp ID '+id);
  const s=matches[0];
  if(normalized(s.name)!==normalized(name))fail('Employee name does not match Staff Master');
  if(s.status!=='active'||date<s.joining_date||s.leaving_date&&date>s.leaving_date)fail('Employee is inactive or date is outside employment');
  const start=reportTime(startValue),arrival=inValue?reportTime(inValue):null;
  if(!s[shiftField]||reportTime(s[shiftField]).time!==start.time)fail(columns[3]+' does not match Staff Master');
  if(s.shift_start&&s.shift_end&&reportTime(s.shift_end).seconds<reportTime(s.shift_start).seconds)fail('Overnight shifts require manual attendance review');
  if(arrival&&(early?arrival.seconds>start.seconds:arrival.seconds<start.seconds))fail(early?'LogTime is after Shift End; review manually':'LogTime is before Shift Start; review manually');
  const key=s.id+'/'+date;if(seen.has(key))fail('Duplicate employee/date');seen.add(key);
  return {staff_id:s.id,department:s.department,work_date:date,...(early?{shift_end:start.time,out_time:arrival?.time||'',early_grace:Number(s.early_grace||0),early_minutes:arrival?Math.max(0,Math.floor((start.seconds-arrival.seconds)/60)-Number(s.early_grace||0)):null}:{shift_start:start.time,in_time:arrival?.time||'',late_minutes:arrival?Math.floor((arrival.seconds-start.seconds)/60):null})};
 });
}

export function earlyDrafts(report,loaded,department,date){
 const selected=report.filter(r=>r.department===department&&r.work_date===date);
 if(!selected.length)throw Error('No report rows match the loaded department and date');
 const drafts=new Map();
 for(const row of selected){
  const current=loaded.find(r=>r.staff_id===row.staff_id);
  if(!current)throw Error('Reported staff not in loaded attendance; reload and check employment dates');
  if(!['present',''].includes(current.status))throw Error('Existing absent, half-day or holiday attendance needs manual review');
  if(!current.staff?.shift_end||reportTime(current.staff.shift_end).time!==row.shift_end)throw Error('Loaded shift differs from report; reload and check Staff Master');
  if(current.out_next_day)throw Error('Next-day departure requires manual attendance review');
  if(current.in_time&&row.out_time&&reportTime(current.in_time).seconds>=reportTime(row.out_time).seconds)throw Error('Departure must be after the recorded arrival; review manually');
  const reference=`Biometric early report: shift end ${row.shift_end}, departure ${row.out_time||'MISSING'}, grace ${row.early_grace} min`;
  const note=current.note?.includes(reference)?current.note:[current.note,reference].filter(Boolean).join(' · ');
  if(note.length>500)throw Error('Existing note plus report reference exceeds 500 characters');
  const draft={...current,out_time:row.out_time||current.out_time,early_minutes:row.early_minutes??current.early_minutes,calculate_shift:false,out_next_day:false,note};
  if(!row.out_time||attendanceIssues(draft,current.staff).length)draft.status='';
  drafts.set(row.staff_id,draft);
 }
 return drafts;
}

export function lateDrafts(report,loaded,department,date){
 const selected=report.filter(r=>r.department===department&&r.work_date===date);
 if(!selected.length)throw Error('No report rows match the loaded department and date');
 const drafts=new Map();
 for(const row of selected){
  const current=loaded.find(r=>r.staff_id===row.staff_id);
  if(!current)throw Error('Reported staff not in loaded attendance; reload and check employment dates');
  if(!['present',''].includes(current.status))throw Error('Existing absent, half-day or holiday attendance needs manual review');
  if(!current.staff?.shift_start||reportTime(current.staff.shift_start).time!==row.shift_start)throw Error('Loaded shift differs from report; reload and check Staff Master');
  if(current.out_time&&row.in_time&&!current.out_next_day&&reportTime(row.in_time).seconds>=reportTime(current.out_time).seconds)throw Error('Arrival must be before the recorded departure; review manually');
  const reference=`Biometric late report: shift ${row.shift_start}, arrival ${row.in_time||'MISSING'}`;
  const note=current.note?.includes(reference)?current.note:[current.note,reference].filter(Boolean).join(' · ');
  if(note.length>500)throw Error('Existing note plus report reference exceeds 500 characters');
  const draft={...current,in_time:row.in_time||current.in_time,late_minutes:row.late_minutes??current.late_minutes,calculate_shift:false,note};
  if(!row.in_time||attendanceIssues(draft,current.staff).length)draft.status='';
  drafts.set(row.staff_id,draft);
 }
 return drafts;
}
