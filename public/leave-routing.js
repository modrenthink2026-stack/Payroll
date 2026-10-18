export const leaveGroups=[['auto','Automatic from designation / department'],['teacher_staff','Teacher / Staff → Principal'],['principal','Principal → Director'],['director','Director → President'],['support','Substaff / Aayah / Attender / Security → HR'],['president','President — policy not configured']];
export const leaveOffices=[['principal','Principal'],['director','Director'],['president','President'],['hr','HR']];
export function leaveGroup(s={}){
 if(s.leave_group)return s.leave_group;
 const title=(s.designation||'').trim().toLowerCase();
 if(['principal','director','president'].includes(title))return title;
 const text=[s.designation,s.department,s.employment_category].filter(Boolean).join(' ').toLowerCase();
 return /(^|[^a-z])(sub[ -]?staff|aayahs?|ayahs?|aayas?|aayas|attenders?|attendants?|security|securty|watchman|watchmen)([^a-z]|$)/.test(text)?'support':'teacher_staff';
}
export function leaveOffice(s){return {teacher_staff:'principal',principal:'director',director:'president',support:'hr'}[leaveGroup(s)]||null;}
export function officeLabel(office){return leaveOffices.find(([id])=>id===office)?.[1]||'Policy not configured';}
