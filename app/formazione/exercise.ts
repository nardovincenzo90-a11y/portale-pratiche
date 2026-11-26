export const profiles={inserimento:'Inserimento ASO',atpay:'BO ATPAY',recuperi:'Recuperi',admin:'Amministratore',super_admin:'Super Admin'};
export type Role=keyof typeof profiles;
type Case=Record<string,any>;
const email=(role:Role)=>role+'@prova.invalid';
export function createExercise(){
 const stamp=()=>new Date().toISOString();
 let seq=1044;
 const row=(number:number,kind:string,extra:Case={}):Case=>({id:String(number),number,kind,client:kind==='Reclamo'?'':'Cliente prova '+number,phone:kind==='Reclamo'?'':'0000000000',notes:'',complaint_text:'',status:'Nuova',assigned:null,creator:email('inserimento'),created:stamp(),updated:stamp(),due:null,vo:null,recovery_assigned:null,recovery_by:null,recovery_at:null,...extra});
 let cases=[row(1041,'ASO187'),row(1042,'ASO191',{vo:'001234'}),row(1043,'Reclamo',{complaint_text:'Esempio di reclamo: ricontattare il cliente.'}),row(1044,'ASO187',{status:'FK15',vo:'009876',assigned:email('atpay'),technical_status:'Da gestire',technical_requested_at:stamp(),technical_requested_by:email('atpay')})];
 let events:Case[]=[];
 let accessAudit:Case[]=[];
 const accessRequests=[{id:'request-1',status:'pending',email:email('inserimento'),name:'Inserimento ASO di prova',reason:'Richiesta di abilitazione al lavoro BO ATPAY',code:'PROVA-01'}];
 const names=Object.keys(profiles) as Role[];
 const members:Case[]=names.map(role=>({id:role,email:email(role),name:profiles[role]+' di prova',role,active:true,can_recover:false}));
 const admin=(role:Role)=>role==='admin'||role==='super_admin';
 const work=(role:Role)=>admin(role)||role==='atpay';
 const recover=(role:Role)=>admin(role)||role==='recuperi';
 const complaints=(role:Role)=>work(role)||recover(role);
 const queue=()=>cases.filter(c=>c.kind!=='Reclamo'&&c.status==='Nuova'&&!c.assigned);
 const demand=(value:unknown,message='Operazione non disponibile in questa esercitazione')=>{if(!value)throw new Error(message)};
 return {
  load(role:Role){
   const visible=cases.filter(c=>admin(role)||c.kind!=='Reclamo'&&(c.creator===email(role)||recover(role)||work(role)&&(c.technical_requested_at||c.assigned===email(role)||queue().includes(c)))||c.kind==='Reclamo'&&complaints(role)&&(c.assigned===email(role)||!c.assigned&&['Nuova','Gestito'].includes(c.status)));
   return {me:{...members.find(m=>m.id===role),role,can_recover:false},cases:structuredClone(visible),team:admin(role)?structuredClone(members.filter(m=>m.id!=='super_admin')):[],events:admin(role)?[...events]:[],online:[],queue:{count:queue().length,minutes:queue().length*8},accessRequests:admin(role)?structuredClone(accessRequests):[],accessAudit:admin(role)?[...accessAudit]:[],teamSOS:[],note:'',announcement:{},resources:[]};
  },
  act(role:Role,b:Case){
   const actor=email(role),op=b.action;
   let c=cases.find(x=>x.id===b.id);
   switch(op){
    case 'create': c=row(++seq,b.kind,{creator:actor,client:b.client,requested_service:b.requested_service||null,phone:b.phone,notes:b.notes,vo:b.vo||null});cases.push(c);break;
    case 'claim':
     if(b.kind==='Reclamo'){demand(complaints(role)&&c?.kind==='Reclamo'&&!c.assigned&&['Nuova','Gestito'].includes(c.status));}
     else{demand(work(role));if(cases.some(x=>x.kind!=='Reclamo'&&x.status==='In lavorazione'&&x.assigned===actor))return {existing:true};c=queue()[0];demand(c,'Nessuna pratica disponibile');}
     Object.assign(c!,{status:'In lavorazione',assigned:actor,updated:stamp()});break;
    case 'saveCaseNote':case 'update':
     demand(c&&(admin(role)||c.assigned===actor&&(c.kind==='Reclamo'?complaints(role):work(role))));
     Object.assign(c!,{notes:b.notes||'',updated:stamp()});
     if(op==='saveCaseNote')break;
     Object.assign(c!,{status:b.status,due:b.due||null,outcome_at:stamp(),recovery_assigned:null});
     if(b.vo&&b.status==='Differita')c!.vo=b.vo;
     if(c!.kind==='Reclamo'&&b.status==='Gestito')c!.assigned=null;
     if(c!.kind==='Reclamo'&&b.status==='Chiusa')cases=cases.filter(x=>x!==c);
     if(b.request_technical||b.status==='Aprire segnalazione tecnica') Object.assign(c!,{technical_status:'Da gestire',technical_requested_at:stamp(),technical_requested_by:actor});
     break;
    case 'recoveryClaim': demand(recover(role)&&c?.kind!=='Reclamo'&&c?.status==='Nuova'&&!c.assigned&&!c.recovery_assigned);c!.recovery_assigned=actor;break;
    case 'recoveryRelease':case 'recoveryVO':case 'recoveryOutcome':case 'recoveryDefer':
     demand(recover(role)&&c&&(admin(role)||c.recovery_assigned===actor));
     if(op!=='recoveryRelease'){if(op!=='recoveryVO'){demand(c!.status==='Nuova'&&!c!.assigned);Object.assign(c!,{status:op==='recoveryDefer'?'Differita':b.status,due:b.due||null,updated:stamp()});}else demand(['Nuova','In lavorazione'].includes(c!.status));Object.assign(c!,{vo:b.vo||c!.vo,recovery_by:actor,recovery_at:stamp()});}
     c!.recovery_assigned=null;break;
    case 'technicalRequest': demand(work(role)&&c&&(admin(role)||c.assigned===actor)&&!c.technical_requested_at);Object.assign(c!,{technical_status:'Da gestire',technical_requested_at:stamp(),technical_requested_by:actor});break;
    case 'technicalClaim': demand(work(role)&&c?.technical_status==='Da gestire');Object.assign(c!,{technical_status:'In lavorazione',technical_assigned:actor});break;
    case 'technicalRelease':case 'technicalSave':case 'technicalComplete':
     demand(work(role)&&c?.technical_status==='In lavorazione'&&(admin(role)||c.technical_assigned===actor));
     if(op==='technicalRelease')Object.assign(c!,{technical_status:'Da gestire',technical_assigned:null});
     else{Object.assign(c!,{technical_reference:b.technical_reference||'',technical_notes:b.technical_notes||''});if(op==='technicalComplete'){demand(b.technical_reference?.trim(),'Indica il numero della segnalazione');Object.assign(c!,{technical_status:'Gestita',technical_closed_at:stamp()});}}
     break;
    case 'technicalReopen': demand(admin(role)&&c?.technical_status==='Gestita');Object.assign(c!,{technical_status:'Da gestire',technical_assigned:null,technical_closed_at:null});break;
    case 'deleteCase': demand(admin(role)&&c&&b.confirmation===String(c.number));cases=cases.filter(x=>x!==c);break;
    case 'deleteCases': demand(admin(role)&&b.ids?.length&&b.confirmation==='ELIMINA '+b.ids.length);cases=cases.filter(x=>!b.ids.includes(x.id));return {deleted:b.ids.length};
    case 'member': {
     const member=members.find(u=>u.email===b.email&&u.id!=='super_admin');
     demand(admin(role)&&member&&['inserimento','atpay','recuperi','admin'].includes(b.role),'Seleziona un utente di prova dalla lista');
     Object.assign(member!,{name:b.name,role:b.role,active:b.active,can_recover:b.can_recover});
     accessAudit.unshift({id:crypto.randomUUID(),created:stamp(),actor,target_email:b.email,action:'Permessi aggiornati'});
     break;
    }
    case 'decideRole': {
     const request=accessRequests.find(item=>item.id===b.id&&item.status==='pending');
     demand(admin(role)&&request&&['approve','reject'].includes(b.decision));
     request!.status=b.decision==='approve'?'approved':'rejected';
     if(b.decision==='approve')members.find(u=>u.email===request!.email)!.role='atpay';
     accessAudit.unshift({id:crypto.randomUUID(),created:stamp(),actor,target_email:request!.email,action:b.decision==='approve'?'Accesso BO approvato':'Accesso BO rifiutato'});
     break;
    }
    default: throw new Error('Questa funzione è disponibile in sola consultazione durante la formazione.');
   }
   if(c)events.unshift({id:crypto.randomUUID(),case_id:c.id,at:stamp(),actor,action:op+' · pratica #'+c.number});
   return {number:c?.number};
  }
 };
}
