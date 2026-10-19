export function paidLeaveTypes(policies){return policies.filter(p=>p.paid).sort((a,b)=>{const order=['CL','EL','SL'];const rank=p=>order.includes(p.code)?order.indexOf(p.code):3;return rank(a)-rank(b)||a.code.localeCompare(b.code);});}
export function balanceEntry(staff,values){
 const balances={},expected_balances={};
 for(const [code,value] of Object.entries(values)){
  if(String(value).trim()==='')continue;
  const n=Number(value);if(!Number.isFinite(n)||n<0||n>9999.5||!Number.isInteger(n*2))throw Error('Enter balances from 0 to 9999.5 days in half-day steps');
  balances[code]=n;expected_balances[code]=Number(staff.leave_balances?.[code]||0);
 }
 if(!Object.keys(balances).length)throw Error('Enter at least one balance for each selected staff member');
 return {staff_id:staff.id,balances,expected_balances};
}
