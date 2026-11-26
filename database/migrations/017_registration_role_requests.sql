alter table portal_internal.portal_enrollment
  add column requested_role text check (requested_role in ('inserimento','recuperi','atpay')),
  add column role_processed_at timestamptz;

alter table portal_internal.portal_access_requests
  add column requested_role text not null default 'atpay' check (requested_role in ('recuperi','atpay'));

create or replace function public.portal_enrollment_service(operation text, details jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare enrollment portal_internal.portal_enrollment;
begin
  if operation = 'request' then
    insert into portal_internal.portal_enrollment as e(work_email,recovery_email,name,requested_role)
      values(details->>'work_email',details->>'recovery_email',details->>'name',
        coalesce(details->>'requested_role','inserimento'))
      on conflict(work_email,recovery_email) do update set requested_role=excluded.requested_role
      where e.approved_at is null and e.role_processed_at is null;
    return null;
  end if;
  if operation = 'reserve_send' then
    update portal_internal.portal_enrollment e set last_sent_at = now()
      where e.work_email = details->>'work_email' and e.approved_at is not null
        and (not (details ? 'recovery_email') or e.recovery_email = details->>'recovery_email')
        and (e.last_sent_at is null or e.last_sent_at < now() - interval '2 minutes')
        and not exists(select 1 from portal_internal.portal_members m where m.email=e.work_email and not m.active)
      returning * into enrollment;
    return case when found then to_jsonb(enrollment) else null end;
  end if;
  raise exception 'Operazione non valida';
end;
$$;
revoke all on function public.portal_enrollment_service(text,jsonb) from public, anon, authenticated;
grant execute on function public.portal_enrollment_service(text,jsonb) to service_role;


create or replace function portal_internal.portal_member()
returns portal_internal.portal_members
language plpgsql security definer set search_path = '' as $$
declare
  u auth.users;
  m portal_internal.portal_members;
  enrollment portal_internal.portal_enrollment;
  login_email text;
begin
  if auth.uid() is null then raise exception 'Accesso richiesto'; end if;
  select * into u from auth.users where id=auth.uid();
  if u.email_confirmed_at is null then raise exception 'Conferma prima la tua email'; end if;
  login_email := lower(u.email);
  if login_email !~ '^[^ @]+@konecta\.com$' and login_email<>'nardovincenzo90@gmail.com' then
    raise exception 'È richiesta una email @konecta.com';
  end if;

  select * into m from portal_internal.portal_members where email=login_email;
  if not found then
    if login_email !~ '^[^ @]+@konecta\.com$' then raise exception 'Utente non abilitato'; end if;
    -- An existing member row is authoritative, including an administrator's manual changes.
    insert into portal_internal.portal_members(email,name,role)
      values(login_email,left(coalesce(nullif(u.raw_user_meta_data->>'name',''),split_part(login_email,'@',1)),120),
        case when exists(select 1 from portal_internal.portal_team_sos s where s.email=login_email and s.active)
          then 'atpay' else 'inserimento' end)
      on conflict(email) do nothing;
    select * into m from portal_internal.portal_members where email=login_email;
  end if;
  if not m.active then raise exception 'Account disattivato'; end if;

  if exists(select 1 from portal_internal.portal_enrollment e
      where e.work_email=login_email and e.approved_at is not null
        and e.requested_role is not null and e.role_processed_at is null) then
    select * into m from portal_internal.portal_members where id=m.id for update;
    if not m.active then raise exception 'Account disattivato'; end if;
    update portal_internal.portal_enrollment e set role_processed_at=now()
      where e.work_email=login_email and e.approved_at is not null
        and e.requested_role is not null and e.role_processed_at is null
      returning * into enrollment;
    if found and (
        (enrollment.requested_role='recuperi' and m.role in ('inserimento','atpay') and not m.can_recover)
        or (enrollment.requested_role='atpay' and m.role='inserimento')
      ) and not exists (
        select 1 from portal_internal.portal_access_audit a
        where a.target_email=m.email and a.created>=enrollment.created_at
          and a.action like 'Permessi aggiornati:%'
      ) then
      insert into portal_internal.portal_access_requests(member_id,requested_role,reason)
        values(m.id,enrollment.requested_role,'Ruolo richiesto in registrazione')
        on conflict(member_id) do nothing;
      if found then
        insert into portal_internal.portal_access_audit(actor,target_email,action)
          values(m.email,m.email,case when enrollment.requested_role='recuperi' then
            'Richiesta accesso Recuperi in registrazione' else 'Richiesta accesso BO in registrazione' end);
      end if;
    end if;
  end if;
  return m;
end;
$$;

CREATE OR REPLACE FUNCTION portal_internal.portal_mutate(actor_email text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m portal_internal.portal_members;c portal_internal.portal_cases;cid uuid;op text:=payload->>'action';state text:=payload->>'status';when_due timestamptz;local_due time;message text;i integer:=0;target_member portal_internal.portal_members;request_row portal_internal.portal_access_requests;previous_email text;
begin
 m:=portal_internal.portal_member();
 select * into m from portal_internal.portal_members where id=m.id for update;
 if not m.active then raise exception 'Account disattivato';end if;
 if op in ('recoveryClaim','recoveryRelease','recoveryVO','recoveryOutcome','recoveryDefer') then
  if m.role not in ('admin','super_admin','recuperi') and not m.can_recover then raise exception 'Accesso Recuperi non autorizzato';end if;
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found or c.kind='Reclamo' then raise exception 'Pratica non disponibile per Recuperi';end if;
  cid:=c.id;
  if op='recoveryClaim' then
   if c.status<>'Nuova' or c.assigned is not null then raise exception 'Pratica già presa in carico dal BO o non disponibile';end if;
   if c.recovery_assigned is not null and c.recovery_assigned<>m.email and c.recovery_claimed_at>now()-interval '30 minutes' then raise exception 'Pratica già seguita da un altro addetto Recuperi';end if;
   update portal_internal.portal_cases set recovery_assigned=m.email,recovery_claimed_at=now() where id=c.id;
   message:='Recuperi: scelta pratica per VO';
  else
   if m.role not in ('admin','super_admin') and c.recovery_assigned is distinct from m.email then raise exception 'Questa pratica non è assegnata a te nei Recuperi';end if;
   if op='recoveryRelease' then
    update portal_internal.portal_cases set recovery_assigned=null,recovery_claimed_at=null where id=c.id;
    message:='Recuperi: assegnazione rilasciata';
   elsif op='recoveryVO' then
    if c.status not in ('Nuova','In lavorazione') then raise exception 'Pratica già chiusa o differita: aggiorna l’elenco';end if;
    if coalesce(payload->>'vo','') !~ '^[0-9]{1,40}$' then raise exception 'Inserisci soltanto il numero VO, da 1 a 40 cifre';end if;
    update portal_internal.portal_cases set vo=payload->>'vo',recovery_by=m.email,recovery_at=now(),recovery_assigned=null,recovery_claimed_at=null where id=c.id;
    message:='Recuperi: VO registrato; ordine BO invariato';
   else
    if c.status<>'Nuova' or c.assigned is not null then raise exception 'Il BO ha già preso la pratica: puoi aggiungere il VO, ma non cambiarne lo stato dai Recuperi';end if;
    if op='recoveryDefer' then
     when_due:=(payload->>'due')::timestamptz;local_due:=(when_due at time zone 'Europe/Rome')::time;
     if when_due is null or when_due<=now() or local_due<'08:00' or local_due>'22:00' or coalesce(payload->>'vo','') !~ '^[0-9]{1,40}$' then raise exception 'Differita: data futura, orario italiano 08–22 e numero VO obbligatorio';end if;
     state:='Differita';
    else
     if coalesce(state,'') not in ('FK15','FK30','FK03','Rifiuto','Nongestibile','Improprio','In carico altro operatore','Messa in 115','Chiusa non fatturata','NON RISPONDE','ONSITE 191','ONSITE 187','RISOLTO CLIENTE','Aprire segnalazione tecnica') then raise exception 'Esito di chiusura non valido';end if;
     if coalesce(payload->>'vo','')<>'' and payload->>'vo' !~ '^[0-9]{1,40}$' then raise exception 'Numero VO non valido';end if;
    end if;
    update portal_internal.portal_cases set status=state,outcome_at=case when state='Differita' then null else now() end,vo=coalesce(nullif(payload->>'vo',''),c.vo),due=when_due,updated=now(),recovery_by=m.email,recovery_at=now(),recovery_assigned=null,recovery_claimed_at=null where id=c.id;
    message:='Recuperi: '||c.status||' → '||state;
   end if;
  end if;
 elsif op='requestBO' then
  if m.role<>'inserimento' then raise exception 'Sei già abilitato alla gestione';end if;
  insert into portal_internal.portal_access_requests(member_id,staff_code,reason) values(m.id,left(trim(coalesce(payload->>'staff_code','')),50),left(coalesce(payload->>'reason',''),1000)) on conflict(member_id) do update set staff_code=excluded.staff_code,reason=excluded.reason,requested_role='atpay',status='pending',created=now(),decided_by=null where portal_access_requests.status<>'pending' or portal_access_requests.requested_role='atpay';
  insert into portal_internal.portal_access_audit(actor,target_email,action) values(m.email,m.email,'Richiesta accesso BO');
 elsif op in ('decideBO','decideRole') then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  select * into request_row from portal_internal.portal_access_requests where id=(payload->>'id')::uuid;
  if not found then raise exception 'Richiesta non trovata';end if;
  select * into target_member from portal_internal.portal_members where id=request_row.member_id for update;
  select * into request_row from portal_internal.portal_access_requests where id=request_row.id for update;
  if request_row.status<>'pending' then raise exception 'Richiesta non più in attesa';end if;
  if op='decideBO' and request_row.requested_role<>'atpay' then raise exception 'Aggiorna il portale per gestire la richiesta Recuperi';end if;
  if payload->>'decision'='approve' then
   if not target_member.active then raise exception 'Prima riattiva l’account';end if;
   update portal_internal.portal_members
      set role=case
        when role in ('admin','super_admin') then role
        when request_row.requested_role='recuperi' and role='atpay' then role
        else request_row.requested_role
      end,
      can_recover=can_recover or (request_row.requested_role='recuperi' and role='atpay') or (request_row.requested_role='atpay' and role='recuperi')
      where id=request_row.member_id;
   update portal_internal.portal_access_requests set status='approved',decided_by=m.email where id=request_row.id;
  elsif payload->>'decision'='reject' then update portal_internal.portal_access_requests set status='rejected',decided_by=m.email where id=request_row.id;
  else raise exception 'Decisione non valida';end if;
  insert into portal_internal.portal_access_audit(actor,target_email,action) values(m.email,target_member.email,'Accesso '||case when request_row.requested_role='recuperi' then 'Recuperi' else 'BO' end||
      case when payload->>'decision'='approve' then ' approvato' else ' rifiutato' end);
 elsif op='staffSave' then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  if length(trim(coalesce(payload->>'matricola','')))=0 or length(trim(coalesce(payload->>'cognome','')))=0 or length(trim(coalesce(payload->>'nome','')))=0 then raise exception 'Matricola, cognome e nome obbligatori';end if;
  if coalesce(payload->>'email','')<>'' and lower(payload->>'email') !~ '^[^ @]+@konecta\.com$' then raise exception 'Email aziendale non valida';end if;
  select email into previous_email from portal_internal.portal_team_sos where matricola=trim(payload->>'matricola') for update;
  insert into portal_internal.portal_team_sos(matricola,cognome,nome,codice_konecta,am_ricavi,email,active) values(trim(payload->>'matricola'),left(trim(payload->>'cognome'),120),left(trim(payload->>'nome'),120),left(trim(coalesce(payload->>'codice_konecta','')),50),left(coalesce(payload->>'am_ricavi',''),120),nullif(lower(trim(payload->>'email')),''),coalesce((payload->>'active')::boolean,true)) on conflict(matricola) do update set cognome=excluded.cognome,nome=excluded.nome,codice_konecta=excluded.codice_konecta,am_ricavi=excluded.am_ricavi,email=excluded.email,active=excluded.active;
  if previous_email is not null and previous_email is distinct from nullif(lower(trim(payload->>'email')),'') then update portal_internal.portal_members set role='inserimento' where email=previous_email and role='atpay';end if;
  if nullif(lower(trim(payload->>'email')),'') is not null then
   if coalesce((payload->>'active')::boolean,true) then
    insert into portal_internal.portal_members(email,name,role) values(lower(trim(payload->>'email')),trim(payload->>'nome')||' '||trim(payload->>'cognome'),'atpay') on conflict(email) do update set role=case when portal_members.role in ('admin','super_admin') then portal_members.role else 'atpay' end,can_recover=portal_members.can_recover or portal_members.role='recuperi';
   else update portal_internal.portal_members set role='inserimento' where email=lower(trim(payload->>'email')) and role='atpay';end if;
  end if;
  insert into portal_internal.portal_access_audit(actor,target_email,action) values(m.email,coalesce(nullif(payload->>'email',''),payload->>'matricola'),'Anagrafica BO aggiornata');
 elsif op='create' then
  if payload->>'kind'='Reclamo' and m.role not in ('admin','super_admin') then raise exception 'Solo gli amministratori inseriscono i reclami';end if;
  if coalesce(payload->>'kind','') not in ('ASO187','ASO191','ATPAY','Reclamo') or length(trim(coalesce(payload->>'client','')))=0 or length(coalesce(payload->>'client',''))>50 or length(coalesce(payload->>'phone',''))>50 or length(coalesce(payload->>'notes',''))>5000 then raise exception 'Controlla canale, numero cliente, recapito e note';end if;
  if coalesce(payload->>'vo','')<>'' and payload->>'vo' !~ '^[0-9]{1,40}$' then raise exception 'Numero VO: inserisci da 1 a 40 cifre';end if;
  insert into portal_internal.portal_cases(kind,client,phone,notes,priority,creator,vo) values(payload->>'kind',payload->>'client',payload->>'phone',coalesce(payload->>'notes',''),case when payload->>'priority'='Alta' then 'Alta' else 'Normale' end,m.email,nullif(payload->>'vo','')) returning id into cid;
  message:='Pratica inserita';
 elsif op='technicalRequest' then
  if m.role not in ('admin','super_admin','atpay') then raise exception 'Richiesta tecnica non autorizzata';end if;
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found or c.kind='Reclamo' then raise exception 'Pratica non trovata';end if;
  if m.role not in ('admin','super_admin') and c.assigned is distinct from m.email then raise exception 'Puoi richiedere la segnalazione solo per le tue lavorazioni';end if;
  if c.status in ('Nuova','In lavorazione','Differita') then raise exception 'Salva prima l’esito della pratica';end if;
  if c.technical_requested_at is not null then raise exception 'Richiesta tecnica già presente: consulta il bacino';end if;
  update portal_internal.portal_cases set technical_status='Da gestire',technical_requested_at=now(),technical_requested_by=m.email,technical_updated_at=now() where id=c.id;
  cid:=c.id;message:='Richiesta apertura tecnica aggiunta; esito BO conservato: '||c.status;
 elsif op in ('technicalClaim','technicalRelease','technicalSave','technicalComplete','technicalReopen') then
  if m.role not in ('admin','super_admin','atpay') then raise exception 'Accesso Segnalazioni tecniche non autorizzato';end if;
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found or c.kind='Reclamo' or c.technical_requested_at is null then raise exception 'Segnalazione tecnica non disponibile';end if;
  cid:=c.id;
  if op='technicalClaim' then
   if c.technical_status<>'Da gestire' or c.technical_assigned is not null then raise exception 'Segnalazione già presa in carico: aggiorna l’elenco';end if;
   update portal_internal.portal_cases set technical_status='In lavorazione',technical_assigned=m.email,technical_claimed_at=now(),technical_updated_at=now() where id=c.id;
   message:='Segnalazione tecnica presa in carico';
  elsif op='technicalReopen' then
   if m.role not in ('admin','super_admin') or c.technical_status<>'Gestita' then raise exception 'Solo gli amministratori possono riaprire una segnalazione gestita';end if;
   update portal_internal.portal_cases set technical_status='Da gestire',technical_assigned=null,technical_claimed_at=null,technical_closed_at=null,technical_updated_at=now() where id=c.id;
   message:='Segnalazione tecnica riaperta';
  else
   if c.technical_status<>'In lavorazione' or (m.role not in ('admin','super_admin') and c.technical_assigned is distinct from m.email) then raise exception 'Segnalazione non assegnata a te o già gestita';end if;
   if op='technicalRelease' then
    update portal_internal.portal_cases set technical_status='Da gestire',technical_assigned=null,technical_claimed_at=null,technical_updated_at=now() where id=c.id;
    message:='Segnalazione tecnica rilasciata nel bacino';
   else
    if length(coalesce(payload->>'technical_notes',''))>5000 or length(coalesce(payload->>'technical_reference',''))>100 then raise exception 'Controlla numero segnalazione (max 100 caratteri) e note (max 5000)';end if;
    if op='technicalComplete' and length(trim(coalesce(payload->>'technical_reference','')))=0 then raise exception 'Inserisci il numero della segnalazione tecnica aperta';end if;
    update portal_internal.portal_cases set technical_reference=nullif(trim(payload->>'technical_reference'),''),technical_notes=coalesce(payload->>'technical_notes',''),technical_status=case when op='technicalComplete' then 'Gestita' else technical_status end,technical_closed_at=case when op='technicalComplete' then now() else technical_closed_at end,technical_updated_at=now() where id=c.id;
    message:=case when op='technicalComplete' then 'Segnalazione tecnica aperta: '||trim(payload->>'technical_reference') else 'Segnalazione tecnica: dati salvati' end;
   end if;
  end if;
 elsif op='deleteCases' then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  if jsonb_typeof(payload->'ids') is distinct from 'array' then raise exception 'Seleziona gli elementi da eliminare';end if;
  if jsonb_array_length(payload->'ids') not between 1 and 1000 then raise exception 'Seleziona da 1 a 1000 elementi per operazione';end if;
  if (select count(distinct value) from jsonb_array_elements_text(payload->'ids'))<>jsonb_array_length(payload->'ids') then raise exception 'Selezione duplicata';end if;
  if payload->>'confirmation' is distinct from 'ELIMINA '||jsonb_array_length(payload->'ids')::text then raise exception 'Conferma il numero di elementi';end if;
  perform id from portal_internal.portal_cases where id in (select value::uuid from jsonb_array_elements_text(payload->'ids')) order by id for update;
  if (select count(*) from portal_internal.portal_cases where id in (select value::uuid from jsonb_array_elements_text(payload->'ids')))<>jsonb_array_length(payload->'ids') then raise exception 'Uno o più elementi non sono più disponibili: aggiorna la selezione';end if;
  for c in select * from portal_internal.portal_cases where id in (select value::uuid from jsonb_array_elements_text(payload->'ids')) order by id loop
   insert into portal_internal.portal_events(case_id,actor,action) values(c.id,m.email,'Eliminazione multipla: '||c.kind||' #'||c.number||' (stato: '||c.status||')');
   delete from portal_internal.portal_cases where id=c.id;
   i:=i+1;
  end loop;
  return jsonb_build_object('ok',true,'deleted',i);
 elsif op='deleteCase' then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Pratica non trovata o già eliminata';end if;
  if payload->>'confirmation' is distinct from c.number::text then raise exception 'Conferma il numero della pratica da eliminare';end if;
  delete from portal_internal.portal_cases where id=c.id;
  cid:=c.id;message:='Eliminata '||c.kind||' #'||c.number||' (stato: '||c.status||')';
 elsif op='claim' then
  if m.role not in ('admin','super_admin','atpay') and not ((m.role='recuperi' or m.can_recover) and coalesce(payload->>'kind','')='Reclamo') then raise exception 'Accesso BO ATPAY non autorizzato';end if;
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
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Pratica non trovata';end if;
  if m.role not in ('admin','super_admin','atpay') and not ((m.role='recuperi' or m.can_recover) and c.kind='Reclamo') then raise exception 'Non sei abilitato alla lavorazione';end if;
  if m.role not in ('admin','super_admin') and c.assigned is distinct from m.email then raise exception 'Non autorizzato a modificare questa pratica';end if;
  if c.kind<>'Reclamo' and state in ('Gestito','Chiusa') then raise exception 'Esito riservato ai reclami';end if;
  if c.kind='Reclamo' and coalesce(state,'') not in ('Gestito','Chiusa') then raise exception 'Usa Gestito o Chiusa per i reclami';end if;
  if coalesce(state,'') not in ('FK15','FK30','FK03','Rifiuto','Nongestibile','Improprio','Differita','In carico altro operatore','Messa in 115','Chiusa non fatturata','NON RISPONDE','ONSITE 191','ONSITE 187','RISOLTO CLIENTE','Aprire segnalazione tecnica','Gestito','Chiusa') then raise exception 'Esito non valido';end if;
  if length(coalesce(payload->>'notes',''))>5000 then raise exception 'Note troppo lunghe';end if;
  if state='Differita' then
   when_due:=(payload->>'due')::timestamptz;local_due:=(when_due at time zone 'Europe/Rome')::time;
   if when_due is null or when_due<=now() or local_due<'08:00' or local_due>'22:00' or coalesce(payload->>'vo','') !~ '^[0-9]+$' then raise exception 'Differita: data futura, orario italiano 08–22 e VO numerico obbligatori';end if;
  end if;
  if c.kind<>'Reclamo' and state in ('Gestito','Chiusa') then raise exception 'Esito riservato ai reclami';end if;
  if c.kind='Reclamo' and state='Chiusa' then
   delete from portal_internal.portal_cases where id=c.id;
  else
  update portal_internal.portal_cases set status=state,outcome_at=case when state='Differita' then null else now() end,recovery_assigned=null,recovery_claimed_at=null,assigned=case when c.kind='Reclamo' and state='Gestito' then null else assigned end,notes=coalesce(payload->>'notes',''),due=when_due,vo=case when state='Differita' then payload->>'vo' else c.vo end,updated=now() where id=c.id;
  end if;
  cid:=c.id;message:=c.status||' → '||state;
 elsif op='saveCaseNote' then
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found or (m.role not in ('admin','super_admin','atpay') and not ((m.role='recuperi' or m.can_recover) and c.kind='Reclamo')) or (m.role not in ('admin','super_admin') and c.assigned is distinct from m.email) then raise exception 'Non autorizzato';end if;
  update portal_internal.portal_cases set notes=left(coalesce(payload->>'notes',''),5000),updated=now() where id=c.id;
  cid:=c.id;message:='Note aggiornate';
 elsif op='importTeamSOS' then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  for message in select value from regexp_split_to_table(coalesce(payload->>'text',''),E'\n') value where trim(value)<>'' loop
   if lower(split_part(message,E'\t',1))='matricola' then continue;end if;
   if split_part(message,E'\t',1)='' or split_part(message,E'\t',2)='' or split_part(message,E'\t',3)='' then raise exception 'Incolla cinque colonne separate da tabulazioni: matricola, cognome, nome, codice Konecta, AM ricavi';end if;
   insert into portal_internal.portal_team_sos(matricola,cognome,nome,codice_konecta,am_ricavi) values(trim(split_part(message,E'\t',1)),trim(split_part(message,E'\t',2)),trim(split_part(message,E'\t',3)),lower(trim(split_part(message,E'\t',4))),trim(split_part(message,E'\t',5))) on conflict(matricola) do update set cognome=excluded.cognome,nome=excluded.nome,codice_konecta=excluded.codice_konecta,am_ricavi=excluded.am_ricavi;
   i:=i+1;
  end loop;
 elsif op='note' then
  insert into portal_internal.portal_notes(member_id,content) values(m.id,left(coalesce(payload->>'content',''),20000)) on conflict(member_id) do update set content=excluded.content;
 elsif op in ('member','resource','resourceUpdate','resourceDelete','bulkReclami','announcement') then
  if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
  if op='member' then
   if lower(trim(payload->>'email'))='nardovincenzo90@gmail.com' or payload->>'role'='super_admin' then raise exception 'Account Super Admin riservato e non modificabile dalla gestione utenti';end if;
   if lower(coalesce(payload->>'email','')) !~ '^[^ @]+@konecta\.com$' then raise exception 'Email non valida';end if;
   if lower(payload->>'email')=m.email and (payload->>'role'<>'admin' or payload->>'active'='false') then raise exception 'Non puoi rimuovere il tuo ruolo amministratore';end if;
   insert into portal_internal.portal_members(email,name,role,active,can_recover) values(lower(payload->>'email'),coalesce(nullif(payload->>'name',''),payload->>'email'),case when payload->>'role' in ('admin','atpay','inserimento','recuperi') then payload->>'role' else 'inserimento' end,coalesce((payload->>'active')::boolean,true),coalesce((payload->>'can_recover')::boolean,false)) on conflict(email) do update set name=excluded.name,role=excluded.role,active=excluded.active,can_recover=excluded.can_recover;
   update portal_internal.portal_access_requests r
      set status=case when t.active and (t.role=r.requested_role or
        (r.requested_role='recuperi' and t.can_recover)) then 'approved' else 'rejected' end,
        decided_by=m.email
      from portal_internal.portal_members t
      where r.member_id=t.id and t.email=lower(payload->>'email') and r.status='pending';
   insert into portal_internal.portal_access_audit(actor,target_email,action) values(m.email,lower(payload->>'email'),'Permessi aggiornati: '||coalesce(payload->>'role','inserimento')||', attivo='||coalesce(payload->>'active','true')||', recuperi='||coalesce(payload->>'can_recover','false'));
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
   if (coalesce(payload->>'url','')<>'' and payload->>'url' !~ '^https?://[^ /]+') or length(coalesce(payload->>'title','')) not between 1 and 150 then raise exception 'Titolo e collegamento HTTPS obbligatori';end if;
   if op='resourceUpdate' then update portal_internal.portal_resources set title=payload->>'title',type=coalesce(payload->>'type','Link'),url=nullif(payload->>'url','') where id=(payload->>'id')::uuid;
   else
   insert into portal_internal.portal_resources(type,title,url) values(coalesce(payload->>'type','Link'),payload->>'title',nullif(payload->>'url',''));
   end if;
  end if;
 else raise exception 'Operazione non valida';end if;
 if cid is not null and (state='Aprire segnalazione tecnica' or payload->>'request_technical'='true') and op in ('update','recoveryOutcome') then
  if state='Differita' then raise exception 'Concludi la pratica prima di richiedere l’apertura tecnica';end if;
  update portal_internal.portal_cases set technical_status='Da gestire',technical_requested_at=now(),technical_requested_by=m.email,technical_updated_at=now(),recovery_assigned=null,recovery_claimed_at=null where id=cid and technical_requested_at is null;
  message:=message||' — inviata al bacino Segnalazioni tecniche';
 end if;
 if cid is not null then insert into portal_internal.portal_events(case_id,actor,action) values(cid,m.email,message);end if;
 return jsonb_build_object('ok',true,'id',cid,'number',(select number from portal_internal.portal_cases where id=cid),'inserted',i,'warnings',case when op='create' and (coalesce(payload->>'client','') !~ '^[0-9]{5,}$' or coalesce(payload->>'phone','') !~ '^[0-9]{6,}$') then 'Controlla numero cliente e recapito: pratica inserita con avviso, come nel portale originale.' else null end);
end $function$;

CREATE OR REPLACE FUNCTION portal_internal.portal_snapshot(actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m portal_internal.portal_members; result jsonb;
begin
 m:=portal_internal.portal_member();
 with expired as (update portal_internal.portal_cases set recovery_assigned=null,recovery_claimed_at=null where recovery_assigned is not null and recovery_claimed_at<now()-interval '30 minutes' returning id)
 insert into portal_internal.portal_events(case_id,actor,action) select id,'SYSTEM','Assegnazione Recuperi scaduta' from expired;
 update portal_internal.portal_cases set recovery_claimed_at=now() where recovery_assigned=m.email;
 insert into portal_internal.portal_presence(member_id) values(m.id) on conflict(member_id) do update set seen_at=now();
 with released as (update portal_internal.portal_cases set status='Nuova',assigned=null,updated=now() where status='Differita' and due<=now() and (now() at time zone 'Europe/Rome')::time between '08:00' and '22:00' returning id)
 insert into portal_internal.portal_events(case_id,actor,action) select id,'SYSTEM','Differita → Nuova' from released;
 select jsonb_build_object('me',to_jsonb(m),'cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.created desc) from portal_internal.portal_cases c where m.role in ('admin','super_admin') or (c.kind<>'Reclamo' and c.creator=m.email) or (m.role='atpay' and (c.technical_requested_at is not null or c.assigned=m.email or(c.status in ('Nuova','Gestito') and c.assigned is null))) or ((m.role='recuperi' or m.can_recover) and (c.kind<>'Reclamo' or c.assigned=m.email or (c.status in ('Nuova','Gestito') and c.assigned is null)))),'[]'::jsonb),'team',case when m.role in ('admin','super_admin') then coalesce((select jsonb_agg(to_jsonb(t)) from portal_internal.portal_members t where t.role<>'super_admin'),'[]'::jsonb) else '[]'::jsonb end,'events',coalesce((select jsonb_agg(to_jsonb(e)) from(select * from portal_internal.portal_events where m.role in ('admin','super_admin') or actor=m.email order by at desc limit 200)e),'[]'::jsonb),'online',case when m.role in ('admin','super_admin') then coalesce((select jsonb_agg(jsonb_build_object('email',pm.email,'name',pm.name,'seen',pp.seen_at)) from portal_internal.portal_presence pp join portal_internal.portal_members pm on pp.member_id=pm.id where pp.seen_at>now()-interval '2 minutes'),'[]'::jsonb) else '[]'::jsonb end,'announcement',coalesce((select to_jsonb(a) from portal_internal.portal_announcements a where id=1),'{}'::jsonb),'queue',jsonb_build_object('count',(select count(*) from portal_internal.portal_cases where kind<>'Reclamo' and status='Nuova' and assigned is null),'minutes',(select count(*)*8 from portal_internal.portal_cases where kind<>'Reclamo' and status='Nuova' and assigned is null)),'accessRequests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'email',pm.email,'name',pm.name,'code',r.staff_code,'reason',r.reason,'status',r.status,'requested_role',r.requested_role,'created',r.created,'decided_by',r.decided_by) order by r.created desc) from portal_internal.portal_access_requests r join portal_internal.portal_members pm on pm.id=r.member_id where pm.role<>'super_admin' and (m.role in ('admin','super_admin') or r.member_id=m.id)),'[]'::jsonb),'accessAudit',case when m.role in ('admin','super_admin') then coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('actor',case when a.actor='nardovincenzo90@gmail.com' then 'Super Admin' else a.actor end,'target_email',case when a.target_email='nardovincenzo90@gmail.com' then 'Super Admin' else a.target_email end)) from(select * from portal_internal.portal_access_audit order by created desc limit 200)a),'[]'::jsonb) else '[]'::jsonb end,'teamSOS',coalesce((select jsonb_agg(to_jsonb(t) order by t.cognome,t.nome) from portal_internal.portal_team_sos t),'[]'::jsonb),'note',coalesce((select content from portal_internal.portal_notes where member_id=m.id),''),'resources',coalesce((select jsonb_agg(to_jsonb(r)) from portal_internal.portal_resources r),'[]'::jsonb)) into result;
 return result;
end $function$;
