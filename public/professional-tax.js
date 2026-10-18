import {salaryTotals} from './salary.js';
export function professionalTaxSlab(gross){
 const value=Number(gross);if(!Number.isFinite(value)||value<0)throw Error('PT salary base must be a non-negative amount');
 const cents=Math.round(value*100);return cents<=1500000?0:cents<=2000000?150:200;
}
export function professionalTaxPreview(s,{override=null,defaultAmount=0,settings={},month=''}={}){
 if(override!==null&&override!==undefined&&override!=='')return {amount:Number(override),source:'Salary override'};
 const active=settings.pt_auto_slabs===true&&month.slice(0,7)>=(settings.pt_effective_from||'9999-12-31').slice(0,7);
 return active?{amount:professionalTaxSlab(salaryTotals(s).cum_gross),source:'Automatic slabs · full paid month estimate'}:{amount:Number(defaultAmount||0),source:'Tax Inputs default'};
}
