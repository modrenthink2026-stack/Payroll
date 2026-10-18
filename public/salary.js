export const salaryComponents=[['basic','Basic'],['da','DA'],['hra','HRA'],['cca','CCA'],['other','Allowances'],['hod_allowance','HOD/Coordinator Allowances']];
export function salaryTotals(s={}){
 const cents=k=>Math.round(Number(s[k]||0)*100);
 const gross=['basic','da','hra','cca','other'].reduce((n,k)=>n+cents(k),0);
 return {gross:gross/100,cum_gross:(gross+cents('hod_allowance'))/100};
}
export function salaryEarnings(earnings){
 const order=['Basic','DA','HRA','CCA','Allowances','Other allowance','HOD/Coordinator Allowances'];
 return Object.entries(earnings).sort(([a],[b])=>(order.includes(a)?order.indexOf(a):order.length)-(order.includes(b)?order.indexOf(b):order.length));
}
