// Header metadata only. Employee values never belong in source control.
export const rosterFields=["S NO", "Staff Name", "Staff Code", "Biometric Code", "Staff ERPCode", "Staff Department Name", "Date Of Birth", "Sex", "Marital Status", "Marriage Anniversary", "Email", "Alternate Email", "Mobile No", "Alternate No", "Emergency No", "Whatsapp No", "Father Name", "Father Occupation", "Father PhoneNo", "Spouse Name", "Spouse PhoneNo", "Spouse Ocupation", "Address", "Landmark1", "Landmark2", "Country Name", "State Name", "City Name", "AdhaarCard No", "PANCard No", "Passport No", "Government ID", "Caste", "Sub Caste", "Nationality", "CitizenShip", "Religion", "BloodGroup", "Bank Name", "Bank AccountNo", "EPFNo", "UAN", "ESINo", "Bank BranchName", "Bank CityName", "Bank StateName", "Staff Payroll Entity", "IFSCCode", "Designation", "Specialization", "Qualification", "CTET Qualified", "Trained As", "Date Of Joining", "Date Of InActive", "Employment Status", "Previous Experience", "Experience", "Total Experience", "Previous InstitutionName", "Previous Designation", "Security Deposit", "Date", "Payment Mode", "Remarks", "UserType Name", "AccessLevel", "IsDivorced", "MotherName", "Employment Category", "BED Course", "Subjects Assigned", "NameAsPerBank"];
const monthNames=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
export function rosterDate(value){
 const text=String(value||'').trim();if(!text)return null;
 let iso=text;
 const match=text.match(/^(\d{1,2})-([A-Za-z]{3})-(\d{2}|\d{4})$/);
 if(match){const m=monthNames.findIndex(v=>v.toLowerCase()===match[2].toLowerCase());let y=Number(match[3]);if(match[3].length===2)y+=y<=26?2000:1900;if(m<0)throw Error('Unknown date month');iso=String(y)+'-'+String(m+1).padStart(2,'0')+'-'+match[1].padStart(2,'0');}
 if(!/^\d{4}-\d{2}-\d{2}$/.test(iso)||!Number.isFinite(Date.parse(iso))||new Date(iso).toISOString().slice(0,10)!==iso)throw Error('Use YYYY-MM-DD or DD-Mmm-YY dates');return iso;
}
export function prepareRoster(input,existing=[]){
 if(!input.length||input.length>500)throw Error('Upload between 1 and 500 source rows');
 const codes=new Set(existing.map(s=>s.code.toLowerCase())),bios=new Set(existing.map(s=>s.biometric_id).filter(Boolean)),byCode=new Map();
 const warnings=[];
 for(let i=0;i<input.length;i++){
  const raw=input[i];for(const key of Object.keys(raw))if(!rosterFields.includes(key))throw Error('Unknown roster field '+key);
  const source=Object.fromEntries(rosterFields.map(k=>[k,String(raw[k]??'').trim()]));
  const code=source['Staff Code'],name=source['Staff Name'];if(!code||!name)throw Error(`Row ${i+2}: Staff Code and Staff Name are required`);
  const joining=rosterDate(source['Date Of Joining']);if(!joining)throw Error(`Row ${i+2}: Date Of Joining is required`);
  const key=code.toLowerCase();const previous=byCode.get(key);
  if(previous){const changes=rosterFields.filter(k=>!['S NO','Security Deposit'].includes(k)&&previous.personal_details[k]!==source[k]);if(changes.length)throw Error(`Row ${i+2}: conflicting duplicate staff code; review ${changes.join(', ')}`);previous.source_records.push(source);warnings.push(`Rows for one staff code combined; all source rows retained`);continue;}
  if(codes.has(key))throw Error(`Row ${i+2}: Staff code already exists`);codes.add(key);
  const bio=source['Biometric Code'];if(bio&&bios.has(bio))throw Error(`Row ${i+2}: duplicate biometric code`);if(bio)bios.add(bio);
  byCode.set(key,{code,name,email:null,joining_date:joining,leaving_date:rosterDate(source['Date Of InActive']),department:source['Staff Department Name'],designation:source.Designation,biometric_id:bio||null,bank_account:source['Bank AccountNo'],ifsc:source.IFSCCode,pan:source['PANCard No'],uan:source.UAN,esi_number:source.ESINo,personal_details:source,source_records:[source]});
 }
 const rows=[...byCode.values()];const counts=new Map();for(const r of rows){const e=r.personal_details.Email.toLowerCase();if(e)counts.set(e,(counts.get(e)||0)+1);}
 const missingEmails=rows.filter(r=>!r.personal_details.Email).length,sharedEmails=rows.filter(r=>counts.get(r.personal_details.Email.toLowerCase())>1).length;
 return {rows,sourceRows:input.length,combinedRows:input.length-rows.length,missingEmails,sharedEmails,warnings};
}
