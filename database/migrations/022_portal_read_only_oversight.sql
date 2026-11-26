create function portal_internal.can_view_portal(member portal_internal.portal_members)
returns boolean language sql immutable set search_path = '' as $$
 select ($1).active and (($1).role in ('admin','super_admin') or ($1).email='vincenzo.nardo@konecta.com');
$$;
revoke all on function portal_internal.can_view_portal(portal_internal.portal_members) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION portal_internal.portal_snapshot(actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m portal_internal.portal_members; result jsonb; can_view_all boolean;
begin
 m:=portal_internal.portal_member();
 can_view_all:=portal_internal.can_view_portal(m);
 with expired as (update portal_internal.portal_cases set recovery_assigned=null,recovery_claimed_at=null where recovery_assigned is not null and recovery_claimed_at<now()-interval '30 minutes' returning id)
 insert into portal_internal.portal_events(case_id,actor,action) select id,'SYSTEM','Assegnazione Recuperi scaduta' from expired;
 update portal_internal.portal_cases set recovery_claimed_at=now() where recovery_assigned=m.email;
 insert into portal_internal.portal_presence(member_id) values(m.id) on conflict(member_id) do update set seen_at=now();
 perform portal_internal.release_due_practices();
 select jsonb_build_object('me',to_jsonb(m)||jsonb_build_object('can_view_all',can_view_all),'cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.created desc) from portal_internal.portal_cases c where can_view_all or (c.kind<>'Reclamo' and c.creator=m.email) or (m.role='atpay' and (c.technical_requested_at is not null or c.assigned=m.email or(c.status in ('Nuova','Gestito') and c.assigned is null))) or ((m.role='recuperi' or m.can_recover) and (c.kind<>'Reclamo' or c.assigned=m.email or (c.status in ('Nuova','Gestito') and c.assigned is null)))),'[]'::jsonb),'team',case when can_view_all then coalesce((select jsonb_agg(to_jsonb(t)) from portal_internal.portal_members t where t.role<>'super_admin'),'[]'::jsonb) else '[]'::jsonb end,'events',coalesce((select jsonb_agg(to_jsonb(e)) from(select * from portal_internal.portal_events where can_view_all or actor=m.email order by at desc limit 200)e),'[]'::jsonb),'online',case when can_view_all then coalesce((select jsonb_agg(jsonb_build_object('email',pm.email,'name',pm.name,'seen',pp.seen_at)) from portal_internal.portal_presence pp join portal_internal.portal_members pm on pp.member_id=pm.id where pp.seen_at>now()-interval '2 minutes'),'[]'::jsonb) else '[]'::jsonb end,'announcement',coalesce((select to_jsonb(a) from portal_internal.portal_announcements a where id=1),'{}'::jsonb),'queue',jsonb_build_object('count',(select count(*) from portal_internal.portal_cases where kind<>'Reclamo' and status='Nuova' and assigned is null),'minutes',(select count(*)*8 from portal_internal.portal_cases where kind<>'Reclamo' and status='Nuova' and assigned is null)),'accessRequests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'email',pm.email,'name',pm.name,'code',r.staff_code,'reason',r.reason,'status',r.status,'requested_role',r.requested_role,'created',r.created,'decided_by',r.decided_by) order by r.created desc) from portal_internal.portal_access_requests r join portal_internal.portal_members pm on pm.id=r.member_id where pm.role<>'super_admin' and (can_view_all or r.member_id=m.id)),'[]'::jsonb),'accessAudit',case when can_view_all then coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('actor',case when a.actor='nardovincenzo90@gmail.com' then 'Super Admin' else a.actor end,'target_email',case when a.target_email='nardovincenzo90@gmail.com' then 'Super Admin' else a.target_email end)) from(select * from portal_internal.portal_access_audit order by created desc limit 200)a),'[]'::jsonb) else '[]'::jsonb end,'teamSOS',coalesce((select jsonb_agg(to_jsonb(t) order by t.cognome,t.nome) from portal_internal.portal_team_sos t),'[]'::jsonb),'note',coalesce((select content from portal_internal.portal_notes where member_id=m.id),''),'resources',coalesce((select jsonb_agg(to_jsonb(r)) from portal_internal.portal_resources r),'[]'::jsonb)) into result;
 return result;
end $function$;

create or replace function portal_internal.portal_events_day(day text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members; d date; result jsonb;
begin
 m:=portal_internal.portal_member();
 d:=day::date;
 select coalesce(jsonb_agg(to_jsonb(e) order by e.at desc,e.id),'[]'::jsonb) into result from portal_internal.portal_events e
 where e.at >= (d::timestamp at time zone 'Europe/Rome') and e.at < ((d+1)::timestamp at time zone 'Europe/Rome') and (portal_internal.can_view_portal(m) or e.actor=m.email);
 return result;
end $$;

create or replace function portal_internal.portal_access_audit_day(day text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members; d date; result jsonb;
begin
 m:=portal_internal.portal_member();
 if not portal_internal.can_view_portal(m) then raise exception 'Solo amministratori';end if;
 d:=day::date;
 select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('actor',case when a.actor='nardovincenzo90@gmail.com' then 'Super Admin' else a.actor end,'target_email',case when a.target_email='nardovincenzo90@gmail.com' then 'Super Admin' else a.target_email end) order by a.created desc,a.id),'[]'::jsonb) into result from portal_internal.portal_access_audit a
 where a.created >= (d::timestamp at time zone 'Europe/Rome') and a.created < ((d+1)::timestamp at time zone 'Europe/Rome');
 return result;
end $$;

create or replace function public.portal_enrollment_admin(request_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  member portal_internal.portal_members;
  enrollment portal_internal.portal_enrollment;
begin
  member := portal_internal.portal_member();
  if member.role not in ('admin','super_admin') then
    raise exception 'Operazione riservata agli amministratori';
  end if;
  if request_id is null then
    return coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (select id, work_email, recovery_email, name, created_at, approved_at
            from portal_internal.portal_enrollment
            order by created_at desc limit 200) r), '[]'::jsonb);
  end if;
  update portal_internal.portal_enrollment
    set approved_at = coalesce(approved_at, now()), approved_by = coalesce(approved_by, member.email)
    where id = request_id and (
      member.role = 'super_admin' or (work_email <> 'vincenzo.nardo@konecta.com' and not exists (
        select 1 from portal_internal.portal_members m
        where m.email = work_email and portal_internal.can_view_portal(m)
      ))
    )
    returning * into enrollment;
  if not found then raise exception 'Richiesta non trovata'; end if;
  return to_jsonb(enrollment);
end;
$$;
