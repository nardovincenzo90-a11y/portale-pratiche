export const romeDay=(v:string)=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(v));
export function dayStart(day:string){
 const midnight=Date.parse(day+'T00:00:00Z');
 const offset=new Intl.DateTimeFormat('en-US',{timeZone:'Europe/Rome',timeZoneName:'shortOffset'}).formatToParts(new Date(midnight)).find(p=>p.type==='timeZoneName')!.value;
 return midnight-Number(offset.replace('GMT',''))*3600000;
}
export function dayHours(day:string,now=Date.now()){
 const next=new Date(day+'T12:00:00Z');next.setUTCDate(next.getUTCDate()+1);
 return Math.max(0,(Math.min(now,dayStart(next.toISOString().slice(0,10)))-dayStart(day))/3600000);
}
