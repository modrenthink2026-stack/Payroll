import {fullAccess} from './access.js';
const sections=[['upload','Upload Data'],['register','Attendance Register'],['late','Late & Early Review'],['confirmation','HR Confirmation']];
export function attendanceSections(role){
 if(fullAccess(role)||role==='hr')return sections.map(([id,label])=>({id,label}));
 if(role==='accountant')return sections.filter(([id])=>id!=='upload').map(([id,label])=>({id,label}));
 if(['manager','director'].includes(role))return sections.filter(([id])=>['register','late'].includes(id)).map(([id,label])=>({id,label}));
 return [];
}
export function selectedAttendanceSection(role,requested){const allowed=attendanceSections(role);return allowed.some(s=>s.id===requested)?requested:allowed[0]?.id||'';}
