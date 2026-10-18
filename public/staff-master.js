import {salaryPayload} from './salary.js';
// Shared import validation. No employee files or previews are persisted in the browser.
export const staffColumns=['code','name','email','department','designation','joining_date','basic','da','hra','cca','other','hod_allowance','salary_mode','consolidated_amount','biometric_id','shift_name','shift_start','shift_end','break_minutes','late_grace','early_grace','pf_enabled','esi_enabled','deposit_eligible','bank_account','ifsc','pan','uan','esi_number','manager_email','probation_end'];
export const staffTemplate=()=>staffColumns.join(',')+'\r\n';
export function shiftMinutes(start,end,breakMinutes=0){
 if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(start)||!/^([01]\d|2[0-3]):[0-5]\d$/.test(end))throw Error('Shift times must use HH:MM (24-hour format)');
 const minutes=t=>Number(t.slice(0,2))*60+Number(t.slice(3));
 const duration=(minutes(end)-minutes(start)+1440)%1440;
 if(!duration||!Number.isInteger(Number(breakMinutes))||breakMinutes<0||breakMinutes>=duration)throw Error('Shift must have different start/end times and a break shorter than its duration');
 return duration-Number(breakMinutes);
}
export function validateStaffImport(input,existing=[]){
 if(!input.length||input.length>500)throw Error('Upload between 1 and 500 staff rows');
 const codes=new Set(existing.map(s=>s.code.toLowerCase())),emails=new Set(existing.map(s=>(s.email||'').toLowerCase())),bios=new Set(existing.map(s=>s.biometric_id).filter(Boolean));
 return input.map((source,i)=>{
  const fail=message=>{throw Error(`Row ${i+2}: ${message}`);};
  for(const key of Object.keys(source))if(!staffColumns.includes(key))fail('Unknown column '+key+'; use the downloaded template');
  const row=Object.fromEntries(staffColumns.map(k=>[k,String(source[k]??'').trim()]));
  for(const key of ['code','name','email','joining_date','basic'])if(!row[key]&&!(key==='basic'&&row.salary_mode==='consolidated'))fail('Missing '+key);
  row.email=row.email.toLowerCase();
  if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.email))fail('Invalid email');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(row.joining_date)||!Number.isFinite(Date.parse(row.joining_date))||new Date(row.joining_date).toISOString().slice(0,10)!==row.joining_date)fail('Joining date must be a real YYYY-MM-DD date');
  if(codes.has(row.code.toLowerCase())||emails.has(row.email)||row.biometric_id&&bios.has(row.biometric_id))fail('Duplicate staff code, email or biometric ID');
  codes.add(row.code.toLowerCase());emails.add(row.email);if(row.biometric_id)bios.add(row.biometric_id);
  if(row.salary_mode==='consolidated'&&!row.consolidated_amount&&!row.other)fail('Missing consolidated amount');
  for(const key of ['basic','da','hra','cca','other','hod_allowance']){if(!/^\d+(\.\d{1,2})?$/.test(row[key]||'0'))fail(key+' must be a non-negative amount with at most two decimals');row[key]=Number(row[key]||0);if(row[key]>999999999999)fail('Salary amount is too large');}
  row.shift_name=row.shift_name||'General';row.shift_start=row.shift_start||'09:00';row.shift_end=row.shift_end||'18:00';
  for(const key of ['break_minutes','late_grace','early_grace']){if(!/^\d+$/.test(row[key]||'0'))fail(key+' must be whole minutes');row[key]=Number(row[key]||0);if(row[key]>1440)fail(key+' exceeds 1440 minutes');}
  try{shiftMinutes(row.shift_start,row.shift_end,row.break_minutes);}catch(err){fail(err.message);}
  for(const key of ['pf_enabled','esi_enabled','deposit_eligible']){if(!['','true','false','yes','no','1','0'].includes(row[key].toLowerCase()))fail(key+' must be true/false');row[key]=['true','yes','1'].includes(row[key].toLowerCase());}
  if(row.manager_email&&!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.manager_email))fail('Invalid manager email');
  if(row.probation_end&&(!/^\d{4}-\d{2}-\d{2}$/.test(row.probation_end)||!Number.isFinite(Date.parse(row.probation_end))||new Date(row.probation_end).toISOString().slice(0,10)!==row.probation_end))fail('Invalid probation end date');
  row.salary_mode=row.salary_mode||'component';if(!['component','consolidated'].includes(row.salary_mode))fail('Salary mode must be component or consolidated');
  if(row.salary_mode==='consolidated'&&!/^\d+(\.\d{1,2})?$/.test(row.consolidated_amount||row.other||'0'))fail('Invalid consolidated amount');
  return salaryPayload(row);
 });
}
