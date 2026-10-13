export const money = n => new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR',maximumFractionDigits:2}).format(Number(n)||0);
export const esc = v => String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function parseCSV(text){
  if(text.length>2_000_000) throw Error('File exceeds 2 MB');
  const rows=[];let row=[],v='',quoted=false;
  for(let i=0;i<text.length;i++){
    const c=text[i];
    if(c==='"'){if(quoted&&text[i+1]==='"'){v+='"';i++;}else quoted=!quoted;}
    else if(c===','&&!quoted){row.push(v);v='';}
    else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(v);if(row.some(x=>x.trim()))rows.push(row);row=[];v='';}
    else v+=c;
  }
  if(quoted)throw Error('Unclosed quoted CSV field');
  row.push(v);if(row.some(x=>x.trim()))rows.push(row);
  if(!rows.length)throw Error('CSV is empty');
  const heads=rows.shift().map(x=>x.trim().replace(/^\uFEFF/,''));
  if(new Set(heads).size!==heads.length)throw Error('Duplicate CSV header');
  return rows.map((r,i)=>{if(r.length!==heads.length)throw Error(`CSV row ${i+2} has the wrong number of columns`);return Object.fromEntries(heads.map((h,j)=>[h,r[j].trim()]));});
}
export function csvText(rows){
  if(!rows.length)return '';
  const cols=Object.keys(rows[0]);
  const quote=v=>{let s=String(v??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
  return [cols.map(quote).join(','),...rows.map(r=>cols.map(k=>quote(r[k])).join(','))].join('\r\n');
}
export function weightedScore(ratings){
  if(!ratings.length||ratings.some(r=>!Number.isFinite(r.weight)||r.weight<0||!Number.isFinite(r.rating)||r.rating<1||r.rating>5))throw Error('Ratings must be between 1 and 5');
  if(Math.abs(ratings.reduce((s,r)=>s+r.weight,0)-100)>0.0001)throw Error('Assessment weights must total 100%');
  return Math.round(ratings.reduce((s,r)=>s+r.weight*r.rating,0))/100;
}
export const letterTypes=['Offer letter','Appointment letter','Service confirmation','Probation extension','Increment letter','Promotion letter','Transfer letter','Resignation acceptance','Termination letter','Relieving letter','Experience letter','Employment certificate','Salary certificate','Warning letter','Show-cause notice','Performance improvement plan','Contract renewal','Final settlement statement'];
export function letterBody(type,s,c){
  const person=s?.name||'[Candidate name]';
  const opening=`${c.name}\n${c.address||'[Company address]'}\n\n${type}\n\nDear ${person},\n\n`;
  const text={
    'Offer letter':'We are pleased to offer you the position of [Position], based at [Location]. Your proposed joining date is [Date]. Your salary components and applicable terms are set out below.\n\n[Basic, DA, HRA, other allowances, gross salary and employer costs]\n[Offer validity and acceptance conditions]',
    'Appointment letter':`We confirm your appointment as ${s?.designation||'[Designation]'}, with effect from [Date]. You will report to [Manager].\n\n[Approved salary components, probation period and employment terms]`,
    'Service confirmation':'Following the approved probation review, your service is confirmed with effect from [Date].\n\n[Confirmed role and approved terms]',
    'Increment letter':'Following approval of your salary revision, your revised salary will take effect from [Date].\n\n[Approved old/new salary components and arrears treatment]',
    'Relieving letter':`We acknowledge that ${person} is relieved from the position of ${s?.designation||'[Designation]'} with effect from [Last working date], under the approved separation decision.\n\n[Authorized handover and clearance statement]`,
    'Experience letter':`This is to certify that ${person} worked with ${c.name} as ${s?.designation||'[Designation]'} from ${s?.joining_date||'[Joining date]'} to [Last working date].\n\n[Verified duties and authorized factual statement]`,
    'Termination letter':'[Insert reviewed, authorized wording for the specific separation decision, applicable notice, reasons and effective date. Do not issue an unreviewed template.]'
  };
  return opening+(text[type]||'[Insert approved company wording, dates, terms and case reference]')+'\n\nYours sincerely,\n[Authorized signatory]\n[Designation]';
}
