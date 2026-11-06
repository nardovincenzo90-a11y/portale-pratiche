create or replace function portal_internal.portal_mutate(actor_email text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members;c portal_internal.portal_cases;cid uuid;op text:=payload->>'action';state text:=payload->>'status';when_due timestamptz;local_due time;message text;i integer:=0;
begin
 m:=portal_internal.portal_member();
 perform 1 from portal_internal.portal_members where id=m.id for update;
 if op='create' then
  if payload->>'kind'='Reclamo' and m.role<>'admin' then raise exception 'Solo gli amministratori inseriscono i reclami';end if;
  if coalesce(payload->>'kind','') not in ('ASO187','ASO191','ATPAY','Reclamo') or length(trim(coalesce(payload->>'client','')))=0 or length(coalesce(payload->>'client',''))>50 or length(coalesce(payload->>'phone',''))>50 or length(coalesce(payload->>'notes',''))>5000 then raise exception 'Controlla canale, numero cliente, recapito e note';end if;
  insert into portal_internal.portal_cases(kind,client,phone,notes,priority,creator) values(payload->>'kind',payload->>'client',payload->>'phone',coalesce(payload->>'notes',''),case when payload->>'priority'='Alta' then 'Alta' else 'Normale' end,m.email) returning id into cid;
  message:='Pratica inserita';
 elsif op='claim' then
  if m.role not in ('admin','atpay') then raise exception 'Accesso BO ATPAY non autorizzato';end if;
  if payload->>'kind'<>'Reclamo' and exists(select 1 from portal_internal.portal_cases where assigned=m.email and status='In lavorazione' and kind<>'Reclamo') then return jsonb_build_object('ok',true,'existing',true);end if;
  if payload->>'kind'='Reclamo' then
   select id into cid from portal_internal.portal_cases where id=(payload->>'id')::uuid and kind='Reclamo' and status in ('Nuova','Gestito') and assigned is null for update skip locked;
  else
   select id into cid from portal_internal.portal_cases where status='Nuova' and assigned is null and kind<>'Reclamo' order by created,id for update skip locked limit 1;
  end if;
  if cid is null then raise exception 'Nessuna pratica disponibile';end if;
  update portal_internal.portal_cases set status='In lavorazione',assigned=m.email,updated=now() where id=cid;
  message:='Presa in carico';
 elsif op='update' then
  if m.role not in ('admin','atpay') then raise exception 'Non sei abilitato alla lavorazione';end if;
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Pratica non trovata';end if;
  if m.role<>'admin' and c.assigned is distinct from m.email then raise exception 'Non autorizzato a modificare questa pratica';end if;
  if c.kind<>'Reclamo' and state in ('Gestito','Chiusa') then raise exception 'Esito riservato ai reclami';end if;
  if c.kind='Reclamo' and coalesce(state,'') not in ('Gestito','Chiusa') then raise exception 'Usa Gestito o Chiusa per i reclami';end if;
  if coalesce(state,'') not in ('FK15','FK30','FK03','Rifiuto','Nongestibile','Improprio','Differita','In carico altro operatore','Messa in 115','Chiusa non fatturata','NON RISPONDE','ONSITE 191','ONSITE 187','RISOLTO CLIENTE','Gestito','Chiusa') then raise exception 'Esito non valido';end if;
  if length(coalesce(payload->>'notes',''))>5000 then raise exception 'Note troppo lunghe';end if;
  if state='Differita' then
   when_due:=(payload->>'due')::timestamptz;local_due:=(when_due at time zone 'Europe/Rome')::time;
   if when_due is null or when_due<=now() or local_due<'08:00' or local_due>'22:00' or coalesce(payload->>'vo','') !~ '^[0-9]+$' then raise exception 'Differita: data futura, orario italiano 08–22 e VO numerico obbligatori';end if;
  end if;
  if c.kind<>'Reclamo' and state in ('Gestito','Chiusa') then raise exception 'Esito riservato ai reclami';end if;
  if c.kind='Reclamo' and state='Chiusa' then
   delete from portal_internal.portal_cases where id=c.id;
  else
  update portal_internal.portal_cases set status=state,assigned=case when c.kind='Reclamo' and state='Gestito' then null else assigned end,notes=coalesce(payload->>'notes',''),due=when_due,vo=case when state='Differita' then payload->>'vo' else null end,updated=now() where id=c.id;
  end if;
  cid:=c.id;message:=c.status||' → '||state;
 elsif op='saveCaseNote' then
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found or m.role not in ('admin','atpay') or (m.role<>'admin' and c.assigned is distinct from m.email) then raise exception 'Non autorizzato';end if;
  update portal_internal.portal_cases set notes=left(coalesce(payload->>'notes',''),5000),updated=now() where id=c.id;
  cid:=c.id;message:='Note aggiornate';
 elsif op='note' then
  insert into portal_internal.portal_notes(member_id,content) values(m.id,left(coalesce(payload->>'content',''),20000)) on conflict(member_id) do update set content=excluded.content;
 elsif op in ('member','resource','resourceUpdate','resourceDelete','bulkReclami','announcement') then
  if m.role<>'admin' then raise exception 'Solo amministratori';end if;
  if op='member' then
   if lower(coalesce(payload->>'email','')) !~ '^[^ @]+@konecta\.com$' then raise exception 'Email non valida';end if;
   if lower(payload->>'email')=m.email and (payload->>'role'<>'admin' or payload->>'active'='false') then raise exception 'Non puoi rimuovere il tuo ruolo amministratore';end if;
   insert into portal_internal.portal_members(email,name,role,active) values(lower(payload->>'email'),coalesce(nullif(payload->>'name',''),payload->>'email'),case when payload->>'role' in ('admin','atpay','inserimento') then payload->>'role' else 'inserimento' end,coalesce((payload->>'active')::boolean,true)) on conflict(email) do update set name=excluded.name,role=excluded.role,active=excluded.active;
  elsif op='announcement' then
   insert into portal_internal.portal_announcements(id,message,actor) values(1,left(coalesce(payload->>'message',''),3000),m.email) on conflict(id) do update set message=excluded.message,actor=excluded.actor,updated=now();
  elsif op='resourceDelete' then
   delete from portal_internal.portal_resources where id=(payload->>'id')::uuid;
  elsif op='bulkReclami' then
   if length(coalesce(payload->>'text',''))>200000 then raise exception 'Caricamento troppo grande';end if;
   for message in select trim(value) from regexp_split_to_table(coalesce(payload->>'text',''),E'\n') value where trim(value)<>'' loop
    insert into portal_internal.portal_cases(kind,client,phone,complaint_text,creator) values('Reclamo','', '',message,m.email) returning id into cid;
    insert into portal_internal.portal_events(case_id,actor,action) values(cid,m.email,'Reclamo caricato');
    i:=i+1;
   end loop;
   cid:=null;
  elsif op in ('resource','resourceUpdate') then
   if coalesce(payload->>'url','') !~ '^https://[^ /]+' or length(coalesce(payload->>'title','')) not between 1 and 150 then raise exception 'Titolo e collegamento HTTPS obbligatori';end if;
   if op='resourceUpdate' then update portal_internal.portal_resources set title=payload->>'title',type=coalesce(payload->>'type','Link'),url=payload->>'url' where id=(payload->>'id')::uuid;
   else
   insert into portal_internal.portal_resources(type,title,url) values(coalesce(payload->>'type','Link'),payload->>'title',payload->>'url');
   end if;
  end if;
 else raise exception 'Operazione non valida';end if;
 if cid is not null then insert into portal_internal.portal_events(case_id,actor,action) values(cid,m.email,message);end if;
 return jsonb_build_object('ok',true,'id',cid,'number',(select number from portal_internal.portal_cases where id=cid),'inserted',i,'warnings',case when op='create' and (coalesce(payload->>'client','') !~ '^[0-9]{5,}$' or coalesce(payload->>'phone','') !~ '^[0-9]{6,}$') then 'Controlla numero cliente e recapito: pratica inserita con avviso, come nel portale originale.' else null end);
end $$;
