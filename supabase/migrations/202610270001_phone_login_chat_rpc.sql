alter table public.phone_login_challenges
  add column if not exists login_code text;

grant select (login_code) on public.phone_login_challenges to authenticated;

create or replace function public.request_phone_login_message(
  p_phone_number text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  phone_digits text;
  normalized_phone text;
  matching_user_ids uuid[];
  target_user_id uuid;
  random_bytes bytea;
  login_code text;
  request_id uuid;
begin
  phone_digits := regexp_replace(coalesce(p_phone_number, ''), '[^0-9]', '', 'g');

  if not (
    phone_digits ~ '^888[0-9]{6,14}$'
    or phone_digits ~ '^[1-9][0-9]{6,14}$'
  ) then
    raise exception 'invalid_phone_number';
  end if;

  normalized_phone := '+' || phone_digits;

  select array_agg(matched.user_id order by matched.user_id)
  into matching_user_ids
  from (
    select distinct lookup.user_id
    from public.lookup_phone_login_user(normalized_phone) as lookup
  ) as matched;

  if coalesce(cardinality(matching_user_ids), 0) <> 1 then
    return gen_random_uuid();
  end if;

  target_user_id := matching_user_ids[1];

  delete from public.phone_login_challenges
  where created_at < now() - interval '7 days';

  if (
    select count(*)
    from public.phone_login_challenges
    where phone_number = normalized_phone
      and created_at > now() - interval '15 minutes'
  ) >= 5 then
    raise exception 'rate_limited';
  end if;

  random_bytes := pg_catalog.uuid_send(pg_catalog.gen_random_uuid());
  login_code := lpad(
    (
      (
        pg_catalog.get_byte(random_bytes, 0)::bigint * 16777216
        + pg_catalog.get_byte(random_bytes, 1)::bigint * 65536
        + pg_catalog.get_byte(random_bytes, 2)::bigint * 256
        + pg_catalog.get_byte(random_bytes, 3)::bigint
      ) % 1000000
    )::text,
    6,
    '0'
  );

  insert into public.phone_login_challenges (
    user_id,
    phone_number,
    code_ciphertext,
    code_hash,
    requester_ip_hash,
    expires_at,
    login_code
  )
  values (
    target_user_id,
    normalized_phone,
    'sql-chat-message',
    'sql-chat-message',
    'sql-chat-message',
    now() + interval '5 minutes',
    login_code
  )
  returning id into request_id;

  return request_id;
end;
$$;

revoke all on function public.request_phone_login_message(text) from public;
grant execute on function public.request_phone_login_message(text)
  to anon, authenticated;
