export const absenceColumns=['Date','Emp ID','Emp Name','Department','Shift'];
export const absenceTemplateCSV=()=>absenceColumns.join(',')+'\r\n';
const normalized=value=>String(value??'').trim().replace(/\s+/g,' ').toLowerCase();

export function absenceDate(value){
 let iso=value;
 const match=/^(\d{1,2})-([a-z]{3})-(\d{2}|\d{4})$/i.exec(value);
 if(match){
  const month=['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(match[2].toLowerCase())+1;
  iso=`${match[3].length===2?'20'+match[3]:match[3]}-${String(month).padStart(2,'0')}-${match[1].padStart(2,'0')}`;
 }
 if(!/^\d{4}-\d{2}-\d{2}$/.test(iso)||!Number.isFinite(Date.parse(iso))||new Date(iso).toISOString().slice(0,10)!==iso)throw Error('Use a valid date such as 04-Sep-26 or 2026-09-04');
 return iso;
}

export function prepareAbsenceReport(rows,staff){
 if(!rows.length||rows.length>15500)throw Error('Upload 1 to 15,500 absence rows');
 const seen=new Set();
 return rows.map((r,i)=>{
  const fail=message=>{throw Error(`Report row ${i+2}: ${message}`);};
  for(const k of absenceColumns)if(!r[k])fail('Missing '+k);
  const matches=staff.filter(s=>s.biometric_id===r['Emp ID']);
  if(matches.length!==1)fail('Unknown or ambiguous biometric Emp ID '+r['Emp ID']);
  const s=matches[0],date=absenceDate(r.Date);
  if(normalized(s.name)!==normalized(r['Emp Name']))fail('Employee name does not match Staff Master');
  if(normalized(s.department)!==normalized(r.Department))fail('Department does not match Staff Master');
  if(normalized(s.shift_name)!==normalized(r.Shift))fail('Shift does not match Staff Master');
  if(s.status!=='active'||date<s.joining_date||s.leaving_date&&date>s.leaving_date)fail('Employee is inactive or date is outside employment');
  const key=s.id+'/'+date;if(seen.has(key))fail('Duplicate employee/date');seen.add(key);
  return {staff_id:s.id,work_date:date,department:s.department,shift:r.Shift};
 });
}

export function absenceDrafts(report,loaded,department,date){
 const selected=report.filter(r=>r.department===department&&r.work_date===date);
 if(!selected.length)throw Error('No report rows match the loaded department and date');
 const drafts=new Map();
 for(const row of selected){
  const current=loaded.find(r=>r.staff_id===row.staff_id);
  if(!current)throw Error('Reported staff not in loaded attendance; reload and check employment dates');
  const reference='Biometric absence report: '+row.shift;
  const note=current.note?.includes(reference)?current.note:[current.note,reference].filter(Boolean).join(' · ');
  if(note.length>500)throw Error('Existing note plus report reference exceeds 500 characters');
  drafts.set(row.staff_id,{...current,status:'',in_time:'',out_time:'',late_minutes:0,early_minutes:0,calculate_shift:false,out_next_day:false,note});
 }
 return drafts;
}
