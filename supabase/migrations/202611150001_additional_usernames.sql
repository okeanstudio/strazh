create table if not exists public.user_additional_usernames (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null
    check (username ~ '^[A-Za-z0-9_]{3,}$'),
  created_at timestamptz not null default now()
);

create unique index if not exists user_additional_usernames_username_ci_idx
  on public.user_additional_usernames (lower(username));

create index if not exists user_additional_usernames_user_created_idx
  on public.user_additional_usernames (user_id, created_at);

alter table public.user_additional_usernames enable row level security;

drop policy if exists "Users can read additional usernames"
  on public.user_additional_usernames;
create policy "Users can read additional usernames"
  on public.user_additional_usernames
  for select
  to authenticated
  using (true);

revoke all on public.user_additional_usernames from public, anon, authenticated;
grant select on public.user_additional_usernames to authenticated;

create or replace function public.purchase_additional_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user auth.users%rowtype;
  normalized_username text;
  current_balance bigint;
  new_balance bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  normalized_username := lower(btrim(coalesce(p_username, '')));
  if normalized_username !~ '^[a-z0-9_]{3,}$' then
    raise exception 'Username must contain at least 3 letters, digits, or underscores'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(1463897165, 1);

  select *
  into target_user
  from auth.users
  where id = auth.uid()
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if lower(btrim(coalesce(target_user.raw_user_meta_data ->> 'tag', '')))
    = normalized_username
    or exists (
      select 1
      from public.user_additional_usernames
      where lower(username) = normalized_username
    )
    or exists (
      select 1
      from auth.users as existing_user
      where lower(existing_user.raw_user_meta_data ->> 'tag') =
            normalized_username
    ) then
    raise exception 'Username is already taken'
      using errcode = '23505';
  end if;

  if coalesce(target_user.raw_user_meta_data ->> 'encoins', '0') !~ '^[0-9]+$' then
    raise exception 'Invalid Encoins balance'
      using errcode = '22023';
  end if;

  current_balance := coalesce(
    (target_user.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );
  if current_balance < 1000 then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;

  new_balance := current_balance - 1000;

  insert into public.user_additional_usernames (user_id, username)
  values (auth.uid(), normalized_username);

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{encoins}',
    to_jsonb(new_balance),
    true
  )
  where id = auth.uid();

  insert into public.encoins_transactions (
    user_id,
    type,
    amount,
    description,
    balance_before,
    balance_after
  )
  values (
    auth.uid(),
    'spend',
    -1000,
    'Покупка дополнительного юзернейма: @' || normalized_username,
    current_balance::integer,
    new_balance::integer
  );

  return jsonb_build_object(
    'username', normalized_username,
    'balance', new_balance
  );
exception
  when unique_violation then
    raise exception 'Username is already taken'
      using errcode = '23505';
end;
$$;

revoke all on function public.purchase_additional_username(text) from public;
grant execute on function public.purchase_additional_username(text) to authenticated;

drop function if exists public.get_user_by_tag_ci(text);
create function public.get_user_by_tag_ci(p_tag text)
returns table(id uuid, email text, is_primary boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select username_match.id, username_match.email, username_match.is_primary
  from (
    select auth_user.id, auth_user.email, true as is_primary, 0 as priority
    from auth.users as auth_user
    where lower(auth_user.raw_user_meta_data ->> 'tag') =
          lower(btrim(coalesce(p_tag, '')))

    union all

    select auth_user.id, auth_user.email, false as is_primary, 1 as priority
    from auth.users as auth_user
    join public.user_additional_usernames as additional_username
      on additional_username.user_id = auth_user.id
    where lower(additional_username.username) =
          lower(btrim(coalesce(p_tag, '')))
  ) as username_match
  order by username_match.priority
  limit 1;
$$;

revoke all on function public.get_user_by_tag_ci(text) from public;
grant execute on function public.get_user_by_tag_ci(text) to anon, authenticated;

create or replace function public.search_users_by_additional_username(
  p_query text
)
returns table(
  id uuid,
  name text,
  tag text,
  avatar_url text,
  status text,
  matched_username text
)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (auth_user.id)
    auth_user.id,
    coalesce(
      nullif(auth_user.raw_user_meta_data ->> 'name', ''),
      nullif(auth_user.raw_user_meta_data ->> 'full_name', ''),
      'Пользователь'
    ),
    coalesce(auth_user.raw_user_meta_data ->> 'tag', ''),
    auth_user.raw_user_meta_data ->> 'avatar_url',
    coalesce(auth_user.raw_user_meta_data ->> 'status', 'offline'),
    additional_username.username
  from public.user_additional_usernames as additional_username
  join auth.users as auth_user on auth_user.id = additional_username.user_id
  where char_length(btrim(coalesce(p_query, ''))) >= 2
    and position(
      lower(btrim(p_query)) in lower(additional_username.username)
    ) > 0
  order by auth_user.id, additional_username.username
  limit 20;
$$;

revoke all on function public.search_users_by_additional_username(text) from public;
grant execute on function public.search_users_by_additional_username(text)
  to anon, authenticated;
