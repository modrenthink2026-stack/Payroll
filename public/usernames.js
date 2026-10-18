export function usernameOptions(staff){
 return staff.filter(s=>s.status==='active'&&s.user_id&&s.login_name).map(s=>[s.login_name,`${s.login_name} · ${s.name} · ${s.employee_ref||s.code}`]);
}
