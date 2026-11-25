-- Integration check. All fixtures and actions are rolled back, including Auth fixtures.
begin;
do $$
declare uid uuid:=gen_random_uuid(); peer uuid:=gen_random_uuid(); label text:='portal-check-'||gen_random_uuid()::text||'@konecta.com'; other_label text:='portal-check-'||gen_random_uuid()::text||'@konecta.com'; created_case jsonb; x uuid; failed boolean:=false; original_created timestamptz; original_outcome timestamptz:=now()-interval '2 days';
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data) values(uid,label,now(),'{}','{}'),(peer,other_label,now(),'{}','{}');
 insert into portal_internal.portal_members(email,name,role) values(label,'Temporary BO verification','atpay'),(other_label,'Temporary peer verification','atpay') on conflict(email) do update set role='atpay';
 perform set_config('request.jwt.claim.sub',uid::text,true);
 created_case:=public.portal_mutate('{"action":"create","kind":"ASO187","client":"9999999","phone":"9999999","vo":"00123"}'); x:=(created_case->>'id')::uuid;
 select created into original_created from portal_internal.portal_cases where id=x;
 -- Simulate the existing BO assignment before saving its outcome.
 update portal_internal.portal_cases set status='In lavorazione',assigned=label where id=x;
 perform public.portal_mutate(jsonb_build_object('action','update','id',x,'status','FK15','notes','Pratica fatturata'));
 update portal_internal.portal_cases set updated=original_outcome,outcome_at=original_outcome where id=x;
 perform public.portal_mutate(jsonb_build_object('action','technicalRequest','id',x));
 if not exists(select 1 from portal_internal.portal_cases where id=x and status='FK15' and updated=original_outcome and outcome_at=original_outcome and technical_status='Da gestire' and technical_requested_at is not null and created=original_created and vo='00123') then raise exception 'Transfer failed';end if;
 perform public.portal_mutate(jsonb_build_object('action','technicalClaim','id',x));
 perform set_config('request.jwt.claim.sub',peer::text,true);
 begin perform public.portal_mutate(jsonb_build_object('action','technicalComplete','id',x,'technical_reference','TECH-TEST'));exception when others then failed:=true;end;
 if not failed then raise exception 'Other operator could complete work';end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 failed:=false;
 begin perform public.portal_mutate(jsonb_build_object('action','technicalComplete','id',x));exception when others then failed:=true;end;
 if not failed then raise exception 'Missing reference accepted';end if;
 perform public.portal_mutate(jsonb_build_object('action','technicalSave','id',x,'technical_notes','Bozza'));
 perform public.portal_mutate(jsonb_build_object('action','technicalRelease','id',x));
 perform public.portal_mutate(jsonb_build_object('action','technicalClaim','id',x));
 perform public.portal_mutate(jsonb_build_object('action','technicalComplete','id',x,'technical_reference','TECH-TEST','technical_notes','Apertura completata'));
 if not exists(select 1 from portal_internal.portal_cases where id=x and technical_status='Gestita' and status='FK15' and updated=original_outcome and outcome_at=original_outcome and technical_closed_at is not null and vo='00123') then raise exception 'Completion failed';end if;
 failed:=false;
 begin perform public.portal_mutate(jsonb_build_object('action','technicalReopen','id',x));exception when others then failed:=true;end;
 if not failed then raise exception 'BO could reopen';end if;
 update portal_internal.portal_members set role='admin' where email=label;
 perform public.portal_mutate(jsonb_build_object('action','technicalReopen','id',x));
 if not exists(select 1 from portal_internal.portal_cases where id=x and status='FK15' and updated=original_outcome and technical_status='Da gestire' and technical_assigned is null) then raise exception 'Admin reopen failed';end if;
 created_case:=public.portal_mutate('{"action":"create","kind":"ASO191","client":"9999998","phone":"9999998"}'); x:=(created_case->>'id')::uuid;
 update portal_internal.portal_cases set status='In lavorazione',assigned=label where id=x;
 perform public.portal_mutate(jsonb_build_object('action','update','id',x,'status','Rifiuto','request_technical',true));
 if not exists(select 1 from portal_internal.portal_cases where id=x and status='Rifiuto' and technical_status='Da gestire' and outcome_at is not null) then raise exception 'Simultaneous outcome and technical request failed';end if;
end $$;
rollback;
