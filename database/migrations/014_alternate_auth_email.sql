create table portal_internal.portal_enrollment (
  id uuid primary key default gen_random_uuid(),
  work_email text not null check (work_email ~ '^[^[:space:]@]+@konecta[.]com$'),
  recovery_email text not null check (recovery_email <> work_email),
  name text not null,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by text,
  last_sent_at timestamptz,
  unique(work_email, recovery_email)
);
alter table portal_internal.portal_enrollment enable row level security;
revoke all on portal_internal.portal_enrollment from public, anon, authenticated;
create unique index portal_enrollment_approved_work_email
  on portal_internal.portal_enrollment(work_email) where approved_at is not null;

create function public.portal_enrollment_admin(request_id uuid default null)
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
      member.role = 'super_admin' or not exists (
        select 1 from portal_internal.portal_members m
        where m.email = work_email and m.role in ('admin', 'super_admin')
      )
    )
    returning * into enrollment;
  if not found then raise exception 'Richiesta non trovata'; end if;
  return to_jsonb(enrollment);
end;
$$;
revoke all on function public.portal_enrollment_admin(uuid) from public, anon, authenticated;
grant execute on function public.portal_enrollment_admin(uuid) to authenticated;

create function public.portal_enrollment_service(operation text, details jsonb)
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
