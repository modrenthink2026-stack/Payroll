import {parseCSV} from './domain.js';
import {prepareAbsenceReport,absenceDrafts} from './absence-csv.js';
import {prepareLateReport,lateDrafts,prepareEarlyReport,earlyDrafts} from './late-csv.js';
import {attendanceDraft} from './bulk-attendance.js';

export const attendanceKey=row=>row.staff_id+'/'+row.work_date;
export function prepareMonthlyReport(kind,text,staff,month){
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))throw Error('Choose a report month');
 const prepare={absence:(text,staff)=>prepareAbsenceReport(parseCSV(text),staff),late:prepareLateReport,early:prepareEarlyReport}[kind];
 if(!prepare)throw Error('Choose an attendance report type');
 const report=prepare(text,staff);
 if(report.some(r=>r.work_date.slice(0,7)!==month))throw Error('Every report date must be in the selected month; no rows were imported');
 return report;
}

export function stageMonthlyReport(kind,report,snapshots,current=[]){
 const draftRows={absence:absenceDrafts,late:lateDrafts,early:earlyDrafts}[kind];
 if(!draftRows)throw Error('Choose an attendance report type');
 const existing=new Map(current.map(r=>[attendanceKey(r),r]));
 const loaded=new Map(snapshots.map(r=>[attendanceKey(r),r]));
 const groups=new Map();
 for(const row of report){
  const snapshot=loaded.get(attendanceKey(row));
  if(!snapshot)throw Error('Staff or report dates changed; upload again');
  const old=existing.get(attendanceKey(row));
  if(old&&old.source_hash!==snapshot.source_hash)throw Error('Attendance or staff changed since preview; clear the preview and upload again');
  if(snapshot.staff.department!==row.department)throw Error('Department changed; upload again');
  const key=JSON.stringify([row.department,row.work_date]);
  if(!groups.has(key))groups.set(key,[]);
  groups.get(key).push(row);
 }
 for(const rows of groups.values()){
  const {department,work_date}=rows[0];
  const drafts=rows.map(row=>{
   const snapshot=loaded.get(attendanceKey(row));
   return existing.get(attendanceKey(row))||{...attendanceDraft(snapshot),work_date,staff:snapshot.staff,selected:true};
  });
  for(const draft of draftRows(rows,drafts,department,work_date).values()){
   const key=attendanceKey({...draft,work_date});
   existing.set(key,{...draft,work_date,selected:existing.get(key)?.selected??true});
  }
 }
 if(existing.size>15500)throw Error('At most 15,500 employee/date rows per monthly save');
 return [...existing.values()].sort((a,b)=>a.work_date.localeCompare(b.work_date)||a.staff.department.localeCompare(b.staff.department)||a.staff.name.localeCompare(b.staff.name));
}
