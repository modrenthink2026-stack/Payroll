export function holidayRows(settings,calendar,year,department=''){
 const first=Number(year)+'-01-01',last=Number(year)+'-12-31';
 const legacy=(settings?.holidays||[]).filter(d=>d>=first&&d<=last).map(date=>({id:null,name:'Company holiday',from_date:date,to_date:date,departments:[],active:true,legacy:true}));
 const entries=(calendar?.enabled?calendar.items||[]:[]).filter(h=>h.from_date<=last&&h.to_date>=first&&(!department||!h.departments.length||h.departments.includes(department)));
 return [...legacy,...entries].sort((a,b)=>a.from_date.localeCompare(b.from_date)||a.name.localeCompare(b.name));
}
