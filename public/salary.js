export const salaryComponents=[['basic','Basic'],['da','DA'],['hra','HRA'],['cca','CCA'],['other','Allowances'],['hod_allowance','HOD/Coordinator Allowances']];
export const consolidatedValue=s=>s.consolidated_amount!==undefined&&s.consolidated_amount!==''?s.consolidated_amount:s.other||0;
export function salaryPayload(s){
 if(s.salary_mode!=='consolidated')return {...s,salary_mode:s.salary_mode||'component'};
 const amount=consolidatedValue(s);
 return {...s,basic:0,da:0,hra:0,cca:0,other:amount,hod_allowance:0,consolidated_amount:amount};
}
export function salaryTotals(s={}){
 if(s.salary_mode==='consolidated'){const value=Math.round(Number(consolidatedValue(s))*100)/100;return {gross:value,cum_gross:value};}
 const cents=k=>Math.round(Number(s[k]||0)*100);
 const gross=['basic','da','hra','cca','other'].reduce((n,k)=>n+cents(k),0);
 return {gross:gross/100,cum_gross:(gross+cents('hod_allowance'))/100};
}
export function salaryEarnings(earnings){
 const order=['Basic','DA','HRA','CCA','Allowances','Other allowance','HOD/Coordinator Allowances','Consolidated salary'];
 return Object.entries(earnings).sort(([a],[b])=>(order.includes(a)?order.indexOf(a):order.length)-(order.includes(b)?order.indexOf(b):order.length));
}
