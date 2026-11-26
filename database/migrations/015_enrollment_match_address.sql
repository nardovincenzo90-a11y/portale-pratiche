create or replace function public.portal_enrollment_service(operation text, details jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare enrollment portal_internal.portal_enrollment;
begin
  if operation = 'request' then
    insert into portal_internal.portal_enrollment(work_email,recovery_email,name)
      values(details->>'work_email',details->>'recovery_email',details->>'name')
      on conflict(work_email,recovery_email) do nothing;
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
