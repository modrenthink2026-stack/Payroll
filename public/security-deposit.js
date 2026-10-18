import {salaryTotals} from './salary.js';
export function securityDepositEstimate(s,{eligible=false,enabled=false,cap=0,balance=0}={}){
 if(!eligible)return {amount:0,note:'Not applicable'};
 if(!enabled)return {amount:0,note:'Company policy disabled'};
 const remaining=Math.max(0,Math.round(Number(cap)*100)-Math.round(Number(balance)*100));
 const amount=Math.min(Math.round(Math.round(salaryTotals(s).cum_gross*100)/10),remaining)/100;
 return {amount,note:remaining===0?'Deposit cap reached':'Full-month estimate; actual paid days and balance apply'};
}
