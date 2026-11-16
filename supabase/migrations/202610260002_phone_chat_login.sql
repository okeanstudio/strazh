create table if not exists public.phone_login_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phone_number text not null,
  code_ciphertext text not null,
  code_hash text not null,
  requester_ip_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  seen_at timestamptz,
  consumed_at timestamptz,
  attempts integer not null default 0 check (attempts between 0 and 5)
);

create index if not exists phone_login_challenges_user_created_idx
  on public.phone_login_challenges (user_id, created_at desc);

create index if not exists phone_login_challenges_phone_created_idx
  on public.phone_login_challenges (phone_number, created_at desc);

create index if not exists phone_login_challenges_ip_created_idx
  on public.phone_login_challenges (requester_ip_hash, created_at desc);

alter table public.phone_login_challenges enable row level security;
revoke all on public.phone_login_challenges from anon, authenticated;
grant select (
  id,
  user_id,
  phone_number,
  created_at,
  expires_at,
  seen_at,
  consumed_at
) on public.phone_login_challenges to authenticated;
grant all on public.phone_login_challenges to service_role;

drop policy if exists "Users can view their own phone login challenges"
  on public.phone_login_challenges;
create policy "Users can view their own phone login challenges"
  on public.phone_login_challenges
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.lookup_phone_login_user(p_phone_number text)
returns table(user_id uuid, email text)
language sql
stable
security definer
set search_path = ''
as $$
  with requested as (
    select regexp_replace(coalesce(p_phone_number, ''), '[^0-9]', '', 'g')
      as digits
  ),
  matched_users as (
    select auth_user.id, auth_user.email
    from auth.users as auth_user, requested
    where auth_user.email_confirmed_at is not null
      and regexp_replace(
        coalesce(auth_user.raw_user_meta_data ->> 'phone', ''),
        '[^0-9]',
        '',
        'g'
      ) = requested.digits

    union

    select auth_user.id, auth_user.email
    from public.anonymous_phone_numbers as anonymous_number
    join auth.users as auth_user on auth_user.id = anonymous_number.user_id
    where anonymous_number.status = 'active'
      and regexp_replace(anonymous_number.phone_number, '[^0-9]', '', 'g') =
          (select digits from requested)
      and auth_user.email_confirmed_at is not null
  )
  select matched_users.id, matched_users.email
  from matched_users;
$$;

revoke all on function public.lookup_phone_login_user(text) from public;
revoke all on function public.lookup_phone_login_user(text) from anon, authenticated;
grant execute on function public.lookup_phone_login_user(text) to service_role;

create or replace function public.create_phone_login_challenge(
  p_user_id uuid,
  p_phone_number text,
  p_code_ciphertext text,
  p_code_hash text,
  p_requester_ip_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  challenge_id uuid;
begin
  delete from public.phone_login_challenges
  where created_at < now() - interval '7 days';

  if (
    select count(*)
    from public.phone_login_challenges
    where phone_number = p_phone_number
      and created_at > now() - interval '15 minutes'
  ) >= 5 then
    raise exception 'rate_limited';
  end if;

  if (
    select count(*)
    from public.phone_login_challenges
    where requester_ip_hash = p_requester_ip_hash
      and created_at > now() - interval '1 hour'
  ) >= 20 then
    raise exception 'rate_limited';
  end if;

  insert into public.phone_login_challenges (
    user_id,
    phone_number,
    code_ciphertext,
    code_hash,
    requester_ip_hash,
    expires_at
  )
  values (
    p_user_id,
    p_phone_number,
    p_code_ciphertext,
    p_code_hash,
    p_requester_ip_hash,
    now() + interval '5 minutes'
  )
  returning id into challenge_id;

  return challenge_id;
end;
$$;

revoke all on function public.create_phone_login_challenge(
  uuid, text, text, text, text
) from public;
revoke all on function public.create_phone_login_challenge(
  uuid, text, text, text, text
) from anon, authenticated;
grant execute on function public.create_phone_login_challenge(
  uuid, text, text, text, text
) to service_role;

create or replace function public.consume_phone_login_challenge(
  p_challenge_id uuid,
  p_code_hash text
)
returns table(user_id uuid, email text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  challenge public.phone_login_challenges%rowtype;
begin
  select *
  into challenge
  from public.phone_login_challenges
  where id = p_challenge_id
  for update;

  if not found
    or challenge.consumed_at is not null
    or challenge.expires_at <= now()
    or challenge.attempts >= 5 then
    return;
  end if;

  if challenge.code_hash <> p_code_hash then
    update public.phone_login_challenges
    set attempts = attempts + 1
    where id = p_challenge_id;
    return;
  end if;

  update public.phone_login_challenges
  set consumed_at = now()
  where id = p_challenge_id;

  return query
  select auth_user.id, auth_user.email
  from auth.users as auth_user
  where auth_user.id = challenge.user_id
    and auth_user.email_confirmed_at is not null;
end;
$$;

revoke all on function public.consume_phone_login_challenge(uuid, text)
  from public;
revoke all on function public.consume_phone_login_challenge(uuid, text)
  from anon, authenticated;
grant execute on function public.consume_phone_login_challenge(uuid, text)
  to service_role;

create or replace function public.mark_phone_login_challenges_seen()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.phone_login_challenges
  set seen_at = now()
  where user_id = (select auth.uid())
    and seen_at is null;
$$;

revoke all on function public.mark_phone_login_challenges_seen() from public;
grant execute on function public.mark_phone_login_challenges_seen()
  to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'phone_login_challenges'
  ) then
    alter publication supabase_realtime
      add table public.phone_login_challenges;
  end if;
end;
$$;
