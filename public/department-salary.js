export function departmentSalaryRows(staff,salaries,department){
 return staff.filter(s=>s.status==='active'&&(s.department||'')===department).map(s=>({staff:s,salary:salaries.filter(v=>v.staff_id===s.id).sort((a,b)=>b.effective_from.localeCompare(a.effective_from))[0]||null}));
}
