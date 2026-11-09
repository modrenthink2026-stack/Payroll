import {parseCSVRows} from './domain.js';
import {absenceDate} from './absence-csv.js';
import {reportTime} from './late-csv.js';
export const rawBiometricColumns=['Emp ID','Emp Name','Log Date','Logtime','Type'];
export const rawBiometricTemplate=()=>rawBiometricColumns.join(',')+'\r\n';
const norm=s=>String(s??'').trim().replace(/\s+/g,' ').toLowerCase();
export function secondsClock(value){if(!Number.isSafeInteger(Number(value))||Number(value)<0)return '';const n=Number(value);return [Math.floor(n/3600),Math.floor(n/60)%60,n%60].map(n=>String(n).padStart(2,'0')).join(':');}
export function prepareRawBiometric(text,staff,month){
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))throw Error('Choose a report month');
 if(new TextEncoder().encode(text).length>16_000_000)throw Error('Raw file exceeds 16 MB');
 const records=parseCSVRows(text,16_000_000),head=records.shift().map(x=>x.trim().replace(/^\uFEFF/,''));
 if(head.length!==5||head.some((h,i)=>norm(h)!==norm(rawBiometricColumns[i])))throw Error('Use headings: '+rawBiometricColumns.join(', '));
 if(!records.length||records.length>62000)throw Error('Upload 1 to 62,000 raw punch rows');
 const byId=new Map();for(const s of staff){const id=String(s.biometric_id??'');if(!byId.has(id))byId.set(id,[]);byId.get(id).push(s);}
 const punches=[],errors=[],seen=new Set();let duplicates=0;
 records.forEach((r,i)=>{const context={emp_id:String(r[0]??'').trim(),source_name:String(r[1]??'').trim(),master_name:'',department:''};try{
  if(r.length!==5||[r[0],r[2],r[3],r[4]].some(x=>!x.trim()))throw Error('Emp ID, Log Date, Logtime and Type are required');
  const [id,,dateValue,timeValue,type]=r.map(x=>x.trim());
  const candidates=byId.get(id)||[];if(candidates.length!==1)throw Error('Unknown or ambiguous Emp ID '+id+' in this company');
  const s=candidates[0];context.master_name=s.name;context.department=s.department||'';
  const date=absenceDate(dateValue.replace(/^(\d{2})-(\d{2})-(\d{4})$/,'$3-$2-$1'));
  if(date.slice(0,7)!==month)throw Error('Date is outside the selected month');
  if(date<s.joining_date||s.leaving_date&&date>s.leaving_date||s.status==='separated'&&!s.leaving_date)throw Error('Punch is outside employment dates: '+date+'; recorded employment '+s.joining_date+' to '+(s.leaving_date||'present'));
  const time=reportTime(timeValue).time,direction=type.toLowerCase();if(!['in','out'].includes(direction))throw Error('Type must be IN or OUT');
  const key=[s.id,date,time,direction].join('|');if(seen.has(key)){duplicates++;return;}seen.add(key);
  punches.push({biometric_id:id,name:s.name,work_date:date,log_time:time,direction,manual_entry:false});
 }catch(e){errors.push({line:i+2,message:e.message,...context,code:e.message.startsWith('Unknown')?'unknown_id':e.message.startsWith('Punch is outside')?'employment_dates':'invalid_row'});}});
 return {punches,errors,duplicates,total:records.length};
}
export function normalAttendance(row){
 const s=row.staff,a=row.attendance,p=row.punches||[],ins=p.filter(p=>p.direction==='in'),outs=p.filter(p=>p.direction==='out');
 const issues=[];let start,end,arrival,departure;
 try{start=reportTime(s.shift_start).seconds;end=reportTime(s.shift_end).seconds;}catch{issues.push('Missing shift assignment');}
 if(!row.working_day)issues.push('Weekly off / holiday');if(row.leave_count)issues.push('Approved leave: reconcile with HR');
 if(ins.length!==1||outs.length!==1)issues.push('Expected one IN and one OUT; review multiple or missing punches');
 if(p.some(x=>x.manual_entry))issues.push('Manual punch requires HR review');
 if(a)issues.push('Existing reviewed entry is preserved');
 if(start!==undefined&&end!==undefined&&end<=start)issues.push('Overnight shift requires explicit review');
 if(ins.length===1&&outs.length===1){arrival=reportTime(ins[0].time).seconds;departure=reportTime(outs[0].time).seconds;
  if(departure<=arrival)issues.push('OUT must be after IN');
  if(start<43200&&arrival>=43200)issues.push('Afternoon arrival requires review');
  if(end>=43200&&departure<43200)issues.push('Morning departure requires review');
 }
 return {issues,eligible:issues.length===0,late_seconds:arrival===undefined||start===undefined?null:Math.max(0,arrival-start),early_minutes:departure===undefined||end===undefined?null:Math.max(0,Math.floor((end-departure)/60)-Number(s.early_grace||0))};
}
export function rawDepartmentReport(rows,staff,plans=[]){
 const staffMap=new Map(staff.map(s=>[s.id,s])),planMap=new Map(plans.map(p=>[p.staff_id,p]));
 const result=rows.filter(r=>r.working_day||r.punches?.length||r.attendance).map(r=>{
  const s=staffMap.get(r.staff_id)||r.staff,p=r.punches||[],ins=p.filter(p=>p.direction==='in').sort((a,b)=>a.time.localeCompare(b.time)),a=r.attendance;
  const current=!!a&&r.evidence_current!==false;
  const log=current?a.in_time:ins.length===1?ins[0].time:null,shift=current?(a.shift_snapshot?.start||r.staff.shift_start):r.staff.shift_start;
  let seconds=null;try{if(log&&shift)seconds=current&&a.shift_snapshot?.raw_late_seconds!=null?Number(a.shift_snapshot.raw_late_seconds):current?Number(a.raw_late_minutes??a.late_minutes??0)*60:Math.max(0,reportTime(log).seconds-reportTime(shift).seconds);}catch{}
  const plan=planMap.get(r.staff_id),event=plan?.plan?.events.find(e=>e.date===r.work_date),review=plan?.review;
  const validReview=current&&review&&review.source_hash===plan.plan.source_hash;
  const decision=validReview?review.decisions.find(d=>d.attendance_id===event?.attendance_id)?.decision:null;
  return {staff_id:r.staff_id,department:s.department||'Unassigned',emp_id:s.biometric_id||s.code,name:s.name,log_date:r.work_date,shift_time:shift||'',log_time:log||'',type:log?'IN':'',late_seconds:seconds,cumulative_seconds:null,exemption:'',manual_entry:p.some(p=>p.manual_entry)?'Yes':a&&!p.length?'Not recorded':'No',review:!current?'HR review pending':a.shift_snapshot?.raw_late_seconds!=null?'Reviewed — seconds':'Reviewed — legacy whole minutes',decision,eligible_event:!!event,source_current:current,working_day:r.working_day,leave_count:r.leave_count||0,proposed_lop_days:0,approved_lop_days:0};
 });
 const groups=new Map();for(const r of result){if(!groups.has(r.staff_id))groups.set(r.staff_id,[]);groups.get(r.staff_id).push(r);}
 for(const records of groups.values()){
  let cumulative=0;
  for(const r of records.filter(r=>r.late_seconds>0).sort((a,b)=>a.late_seconds-b.late_seconds||a.log_date.localeCompare(b.log_date))){
   // Holidays/approved leave are visible but never consume the payroll late allowance.
   if(!r.working_day||r.leave_count||(r.source_current&&!r.eligible_event)){r.exemption='Excluded from late penalty';continue;}
   cumulative+=r.late_seconds;r.cumulative_seconds=cumulative;
   if(cumulative<=1500)r.exemption='Exemption';else {r.proposed_lop_days=.5;r.exemption=r.decision==='cl'?'CL 0.5 day approved':r.decision==='lop'?'Bio LOP 0.5 day approved':'Proposed Bio LOP 0.5 day — review';if(r.decision==='lop')r.approved_lop_days=.5;}
  }
 }
 return result.sort((a,b)=>a.department.localeCompare(b.department)||a.name.localeCompare(b.name)||a.staff_id.localeCompare(b.staff_id)||(a.late_seconds>0?0:1)-(b.late_seconds>0?0:1)||(a.late_seconds>0&&b.late_seconds>0?a.late_seconds-b.late_seconds:0)||a.log_date.localeCompare(b.log_date));
}
export function rawReportExport(rows){return rows.map(r=>({'Department':r.department,'Emp ID':r.emp_id,'Emp Name':r.name,'Log Date':r.log_date,'Shift Time':r.shift_time,'Logtime':r.log_time,'Type':r.type,'Late Minutes':r.late_seconds===null?'Missing punch / shift':r.late_seconds?secondsClock(r.late_seconds):'No Late','Total Late Minutes':r.cumulative_seconds===null?'':secondsClock(r.cumulative_seconds),'Exemption / Bio LOP':r.exemption,'Manual Entry':r.manual_entry,'Review':r.review}));}
export function rawReportSummary(rows){const map=new Map();for(const r of rows){const key=r.staff_id;if(!map.has(key))map.set(key,{Department:r.department,'Emp ID':r.emp_id,'Emp Name':r.name,'Attendance rows':0,'Late entries':0,seconds:0,'Exempt entries':0,'Proposed adjustment days':0,'Approved Bio LOP days':0,'Pending attendance rows':0});const s=map.get(key);s['Attendance rows']++;if(r.late_seconds>0){s['Late entries']++;s.seconds+=r.late_seconds;}if(r.exemption==='Exemption')s['Exempt entries']++;s['Proposed adjustment days']+=r.proposed_lop_days;s['Approved Bio LOP days']+=r.approved_lop_days;if(!r.source_current)s['Pending attendance rows']++;}return [...map.values()].map(({seconds,...r})=>({...r,'Total late duration':secondsClock(seconds)}));}
export function rawUploadPreview(punches,snapshot,staff){const byId=new Map(staff.map(s=>[String(s.biometric_id),s]));const groups=new Map(snapshot.rows.map(r=>[r.staff_id+'/'+r.work_date,structuredClone(r)]));for(const p of punches){const s=byId.get(p.biometric_id),key=s.id+'/'+p.work_date;let r=groups.get(key);if(!r){r={staff_id:s.id,work_date:p.work_date,staff:s,punches:[],attendance:null,working_day:true,leave_count:0};groups.set(key,r);}if(!r.punches.some(x=>x.time===p.log_time&&x.direction===p.direction)){r.punches.push({time:p.log_time,direction:p.direction,manual_entry:false});r.evidence_current=false;}}return [...groups.values()];}
export function rawDepartmentSummary(rows){const result=new Map();for(const r of rawReportSummary(rows)){const d=r.Department;if(!result.has(d))result.set(d,{Department:d,Employees:0,'Attendance rows':0,'Late entries':0,'Exempt entries':0,'Proposed adjustment days':0,'Approved Bio LOP days':0,'Pending attendance rows':0,seconds:0});const s=result.get(d);s.Employees++;for(const key of ['Attendance rows','Late entries','Exempt entries','Proposed adjustment days','Approved Bio LOP days','Pending attendance rows'])s[key]+=r[key];s.seconds+=r['Total late duration'].split(':').reduce((a,v)=>a*60+Number(v),0);}return [...result.values()].map(({seconds,...r})=>({...r,'Total late duration':secondsClock(seconds)}));}

export function rawValidationIssues(errors){const groups=new Map();for(const e of errors){const key=JSON.stringify([e.emp_id,e.source_name,e.master_name,e.code]);if(!groups.has(key))groups.set(key,{emp_id:e.emp_id||'',source_name:e.source_name||'',master_name:e.master_name||'',department:e.department||'',code:e.code||'invalid_row',message:e.message,count:0,first_line:e.line});groups.get(key).count++;}return [...groups.values()];}
export function rawValidationExport(errors){return rawValidationIssues(errors).map(e=>({'Emp ID':e.emp_id,'File employee name':e.source_name,'Staff Master name':e.master_name,'Department':e.department,'Issue':e.code,'Affected punch rows':e.count,'First file line':e.first_line,'Details':e.message}));}
