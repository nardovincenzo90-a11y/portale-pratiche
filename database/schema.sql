-- Isolated application schema in an existing Supabase project. Existing application tables and Auth settings are not modified.
create schema portal_internal;
revoke all on schema portal_internal from public,anon;
grant usage on schema portal_internal to authenticated;
-- Schema and transaction functions; no production customer data or credentials.
create table portal_internal.portal_members(id uuid primary key default gen_random_uuid(), email text not null unique check(email=lower(email)), name text not null, role text not null default 'operatore' check(role in ('admin','operatore')));
create table portal_internal.portal_cases(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('ASO187','ASO191','ATPAY','Reclamo')),client text not null,phone text not null,notes text not null default '',status text not null default 'Nuova',priority text not null default 'Normale' check(priority in ('Alta','Normale')),assigned text,creator text not null,created timestamptz not null default now(),updated timestamptz not null default now(),due timestamptz,vo text,demo integer not null default 0);
create unique index portal_one_active_case on portal_internal.portal_cases(assigned) where status='In lavorazione';
create index portal_queue on portal_internal.portal_cases(kind,status,priority,created);
create table portal_internal.portal_events(id uuid primary key default gen_random_uuid(),case_id uuid not null,actor text not null,action text not null,at timestamptz not null default now());
create index portal_history on portal_internal.portal_events(at desc);
create table portal_internal.portal_resources(id uuid primary key default gen_random_uuid(),type text not null,title text not null,url text not null check(url ~ '^https://'));
alter table portal_internal.portal_members enable row level security;
alter table portal_internal.portal_cases enable row level security;
alter table portal_internal.portal_events enable row level security;
alter table portal_internal.portal_resources enable row level security;
revoke all on portal_internal.portal_members,portal_internal.portal_cases,portal_internal.portal_events,portal_internal.portal_resources from anon,authenticated;
grant all on portal_internal.portal_members,portal_internal.portal_cases,portal_internal.portal_events,portal_internal.portal_resources to service_role;

create function portal_internal.portal_snapshot(actor_email text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members; result jsonb;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select lower(email) into actor_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if actor_email is null then raise exception 'Email non verificata';end if;
 select * into m from portal_internal.portal_members where email=lower(actor_email);
 if not found then raise exception 'Utente non abilitato';end if;
 with released as (update portal_internal.portal_cases set status='Nuova',assigned=null,updated=now() where status='Differita' and due<=now() returning id)
 insert into portal_internal.portal_events(case_id,actor,action) select id,'SYSTEM','Differita → Nuova' from released;
 select jsonb_build_object('me',to_jsonb(m),'cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.created desc) from portal_internal.portal_cases c where m.role='admin' or c.creator=m.email or c.assigned=m.email or(c.status='Nuova' and c.assigned is null)),'[]'::jsonb),'team',case when m.role='admin' then coalesce((select jsonb_agg(to_jsonb(t)) from portal_internal.portal_members t),'[]'::jsonb) else '[]'::jsonb end,'events',coalesce((select jsonb_agg(to_jsonb(e)) from(select * from portal_internal.portal_events where m.role='admin' or actor=m.email order by at desc limit 200)e),'[]'::jsonb),'resources',coalesce((select jsonb_agg(to_jsonb(r)) from portal_internal.portal_resources r),'[]'::jsonb)) into result;
 return result;
end $$;

create function portal_internal.portal_mutate(actor_email text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members;c portal_internal.portal_cases;cid uuid;op text:=payload->>'action';state text:=payload->>'status';when_due timestamptz;local_due time;message text;i integer;
begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select lower(email) into actor_email from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if actor_email is null then raise exception 'Email non verificata';end if;
 -- Serialise operations by the same member; different operators can work concurrently.
 select * into m from portal_internal.portal_members where email=lower(actor_email) for update;
 if not found then raise exception 'Utente non abilitato';end if;
 if op='create' then
  if coalesce(payload->>'kind','') not in ('ASO187','ASO191','ATPAY','Reclamo') or coalesce(payload->>'client','') !~ '^[0-9]{5,30}$' or coalesce(payload->>'phone','') !~ '^\+?[0-9 -]{6,25}$' or length(coalesce(payload->>'notes',''))>5000 then raise exception 'Controlla canale, numero cliente, recapito e note';end if;
  insert into portal_internal.portal_cases(kind,client,phone,notes,priority,creator) values(payload->>'kind',payload->>'client',payload->>'phone',coalesce(payload->>'notes',''),case when payload->>'priority'='Alta' then 'Alta' else 'Normale' end,m.email) returning id into cid;
  message:='Pratica inserita';
 elsif op='claim' then
  if exists(select 1 from portal_internal.portal_cases where assigned=m.email and status='In lavorazione') then raise exception 'Completa prima la pratica già in lavorazione';end if;
  select id into cid from portal_internal.portal_cases where status='Nuova' and assigned is null and kind=payload->>'kind' order by case priority when 'Alta' then 0 else 1 end,created for update skip locked limit 1;
  if cid is null then raise exception 'Nessuna pratica disponibile';end if;
  update portal_internal.portal_cases set status='In lavorazione',assigned=m.email,updated=now() where id=cid;
  message:='Presa in carico';
 elsif op='update' then
  select * into c from portal_internal.portal_cases where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Pratica non trovata';end if;
  if m.role<>'admin' and c.assigned is distinct from m.email then raise exception 'Non autorizzato a modificare questa pratica';end if;
  if coalesce(state,'') not in ('FK15','FK30','FK03','Rifiuto','Nongestibile','Improprio','Differita','In carico altro operatore','Messa in 115','Chiusa non fatturata','NON RISPONDE','ONSITE 191','ONSITE 187','RISOLTO CLIENTE','Gestito') then raise exception 'Esito non valido';end if;
  if length(coalesce(payload->>'notes',''))>5000 then raise exception 'Note troppo lunghe';end if;
  if state='Differita' then
   when_due:=(payload->>'due')::timestamptz;local_due:=(when_due at time zone 'Europe/Rome')::time;
   if when_due is null or when_due<=now() or local_due<'08:00' or local_due>'22:00' or coalesce(payload->>'vo','') !~ '^[0-9]+$' then raise exception 'Differita: data futura, orario italiano 08–22 e VO numerico obbligatori';end if;
  end if;
  update portal_internal.portal_cases set status=state,notes=coalesce(payload->>'notes',''),due=when_due,vo=case when state='Differita' then payload->>'vo' else null end,updated=now() where id=c.id;
  cid:=c.id;message:=c.status||' → '||state;
 elsif op in ('member','resource') then
  if m.role<>'admin' then raise exception 'Solo amministratori';end if;
  if op='member' then
   if coalesce(payload->>'email','') !~ '^[^ @]+@[^ @]+\.[^ @]+$' then raise exception 'Email non valida';end if;
   if lower(payload->>'email')=m.email and payload->>'role'<>'admin' then raise exception 'Non puoi rimuovere il tuo ruolo amministratore';end if;
   insert into portal_internal.portal_members(email,name,role) values(lower(payload->>'email'),coalesce(nullif(payload->>'name',''),payload->>'email'),case when payload->>'role'='admin' then 'admin' else 'operatore' end) on conflict(email) do update set name=excluded.name,role=excluded.role;
  elsif op='resource' then
   if coalesce(payload->>'url','') !~ '^https://[^ /]+' or length(coalesce(payload->>'title','')) not between 1 and 150 then raise exception 'Titolo e collegamento HTTPS obbligatori';end if;
   insert into portal_internal.portal_resources(type,title,url) values(coalesce(payload->>'type','Link'),payload->>'title',payload->>'url');
  end if;
 else raise exception 'Operazione non valida';end if;
 if cid is not null then insert into portal_internal.portal_events(case_id,actor,action) values(cid,m.email,message);end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function portal_internal.portal_snapshot(text),portal_internal.portal_mutate(text,jsonb) from public,anon,authenticated;
grant execute on function portal_internal.portal_snapshot(text),portal_internal.portal_mutate(text,jsonb) to authenticated;
create function public.portal_snapshot() returns jsonb language sql security invoker set search_path='' as 'select portal_internal.portal_snapshot(null::text)';
create function public.portal_mutate(payload jsonb) returns jsonb language sql security invoker set search_path='' as 'select portal_internal.portal_mutate(null::text,payload)';
revoke all on function public.portal_snapshot(),public.portal_mutate(jsonb) from public,anon;
grant execute on function public.portal_snapshot(),public.portal_mutate(jsonb) to authenticated;
