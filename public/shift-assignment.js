export const shiftDepartments=rows=>[...new Set(rows.filter(s=>s.status==='active').map(s=>s.department||''))].sort((a,b)=>a.localeCompare(b));
export function shiftCandidates(rows,department=null,query=''){
 const q=query.trim().toLowerCase();
 return rows.filter(s=>s.status==='active'&&(department===null||(s.department||'')===department)&&[s.name,s.code,s.employee_ref].join(' ').toLowerCase().includes(q));
}
