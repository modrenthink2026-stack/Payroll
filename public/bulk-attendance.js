export function attendanceIssues(row,staff={}){
 const issues=[];
 if(['absent','holiday'].includes(row.status))return issues;
 const seconds=value=>{const [h,m,s=0]=String(value).split(':').map(Number);return h*3600+m*60+s;};
 if(!row.in_time)issues.push('Missing in punch');
 if(!row.out_time)issues.push('Missing out punch');
 if(row.in_time&&staff.shift_start&&seconds(staff.shift_start)<43200&&seconds(row.in_time)>=43200)issues.push('Afternoon arrival: check permission or a missing morning punch');
 if(row.out_time&&staff.shift_end&&seconds(staff.shift_end)>=43200&&seconds(row.out_time)<43200)issues.push('Morning departure: verify punch direction and attendance');
 if(row.in_time&&row.out_time&&!row.out_next_day&&seconds(row.out_time)<=seconds(row.in_time))issues.push('Departure must be after arrival');
 return issues;
}

export function attendanceDraft(row){const a=row.attendance;return {staff_id:row.staff_id,source_hash:row.source_hash,status:a?.status||'present',in_time:a?.in_time?.slice(0,8)||'',out_time:a?.out_time?.slice(0,8)||'',late_minutes:a?.raw_late_minutes??a?.late_minutes??0,early_minutes:a?.early_minutes??0,calculate_shift:false,out_next_day:a?.shift_snapshot?.out_next_day??false,note:a?.note||''};}

export function attendanceMatches(staff={},query=''){
 const text=[staff.name,staff.code,staff.employee_ref].filter(Boolean).join(' ').toLowerCase();
 return String(query).trim().toLowerCase().split(/\s+/).filter(Boolean).every(term=>text.includes(term));
}
