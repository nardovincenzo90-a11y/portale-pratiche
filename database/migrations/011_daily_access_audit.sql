create or replace function portal_internal.portal_access_audit_day(day text) returns jsonb language plpgsql security definer set search_path='' as $$
declare m portal_internal.portal_members; d date; result jsonb;
begin
 m:=portal_internal.portal_member();
 if m.role not in ('admin','super_admin') then raise exception 'Solo amministratori';end if;
 d:=day::date;
 select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('actor',case when a.actor='nardovincenzo90@gmail.com' then 'Super Admin' else a.actor end,'target_email',case when a.target_email='nardovincenzo90@gmail.com' then 'Super Admin' else a.target_email end) order by a.created desc,a.id),'[]'::jsonb) into result from portal_internal.portal_access_audit a
 where a.created >= (d::timestamp at time zone 'Europe/Rome') and a.created < ((d+1)::timestamp at time zone 'Europe/Rome');
 return result;
end $$;
revoke all on function portal_internal.portal_access_audit_day(text) from public,anon,authenticated;
grant execute on function portal_internal.portal_access_audit_day(text) to authenticated;
create or replace function public.portal_access_audit_day(day text) returns jsonb language sql security invoker set search_path='' as $$ select portal_internal.portal_access_audit_day(day) $$;
revoke all on function public.portal_access_audit_day(text) from public,anon;
grant execute on function public.portal_access_audit_day(text) to authenticated;
