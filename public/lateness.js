// The monthly allowance covers complete arrivals in ascending minute order.
export function allocateLateAllowance(input,allowance=25){
 if(!Number.isInteger(allowance)||allowance<0)throw Error('Invalid monthly allowance');
 let remaining=allowance,used=0,total=0,uncovered=0;
 const normalized=input.map(r=>({...r,minutes:Number(r.minutes)}));
 for(const e of normalized)if(!Number.isInteger(e.minutes)||e.minutes<0)throw Error('Late minutes must be whole non-negative minutes');
 const events=normalized.filter(r=>r.minutes>0).sort((a,b)=>a.minutes-b.minutes||String(a.date).localeCompare(String(b.date))||String(a.attendance_id).localeCompare(String(b.attendance_id)));
 for(const e of events){if(!Number.isInteger(e.minutes)||e.minutes<0)throw Error('Late minutes must be whole non-negative minutes');total+=e.minutes;e.cumulative_minutes=total;e.covered=e.minutes<=remaining;if(e.covered){remaining-=e.minutes;used+=e.minutes;}else uncovered+=e.minutes;}
 return {allowance,total_minutes:total,used_minutes:used,unused_minutes:remaining,net_excess_minutes:Math.max(0,total-allowance),uncovered_minutes:uncovered,events};
}
export function lateSummaryText(plan={}){return `${plan.total_minutes||0} min late · ${plan.used_minutes||0}/25 min allowance used · ${plan.uncovered_minutes||0} min for review`;}

export function minutesClock(value){const n=Number(value);if(!Number.isInteger(n)||n<0)return "";return String(Math.floor(n/60)).padStart(2,"0")+":"+String(n%60).padStart(2,"0");}
