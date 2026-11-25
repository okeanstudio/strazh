create table if not exists public.bots (
  bot_user_id uuid primary key references auth.users(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  tag text not null,
  description text not null default '',
  avatar_url text,
  token_hash text not null,
  is_verified boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists bots_tag_unique
  on public.bots (lower(tag));
create index if not exists bots_owner_idx
  on public.bots(owner_id, created_at desc);

alter table public.bots enable row level security;
drop policy if exists bots_public_read on public.bots;
create policy bots_public_read on public.bots
  for select to authenticated using (true);

create or replace function public.register_bot(
  p_bot_user_id uuid,
  p_owner_id uuid,
  p_name text,
  p_tag text,
  p_description text default '',
  p_avatar_url text default null,
  p_token_hash text default ''
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tag text := lower(regexp_replace(trim(p_tag), '^@+', '', 'g'));
  v_metadata jsonb;
begin
  if auth.uid() is null or auth.uid() <> p_bot_user_id then
    raise exception 'bot_user_id must belong to the current account';
  end if;

  select raw_user_meta_data into v_metadata
  from auth.users where id = p_bot_user_id;

  if coalesce(v_metadata ->> 'is_bot', 'false') <> 'true'
     or coalesce(v_metadata ->> 'bot_owner_id', '') <> p_owner_id::text then
    raise exception 'invalid bot account';
  end if;
  if btrim(p_name) = '' or v_tag = '' or p_token_hash = '' then
    raise exception 'bot name, tag and token are required';
  end if;

  insert into public.bots (
    bot_user_id, owner_id, name, tag, description, avatar_url, token_hash
  ) values (
    p_bot_user_id, p_owner_id, btrim(p_name), v_tag,
    btrim(coalesce(p_description, '')), p_avatar_url, p_token_hash
  )
  on conflict (bot_user_id) do update set
    name = excluded.name,
    tag = excluded.tag,
    description = excluded.description,
    avatar_url = excluded.avatar_url,
    token_hash = excluded.token_hash,
    updated_at = now();
end;
$$;

create or replace function public.get_my_bots()
returns table (
  bot_user_id uuid,
  owner_id uuid,
  name text,
  tag text,
  description text,
  avatar_url text,
  is_verified boolean,
  is_enabled boolean,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select b.bot_user_id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled, b.created_at
  from public.bots b
  where b.owner_id = auth.uid()
  order by b.created_at desc;
$$;

create or replace function public.get_all_bots()
returns table (
  bot_user_id uuid,
  owner_id uuid,
  name text,
  tag text,
  description text,
  avatar_url text,
  is_verified boolean,
  is_enabled boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1
    from auth.users
    where id = auth.uid()
      and (
        raw_user_meta_data ->> 'role' in ('admin', 'owner', 'moderator')
        or raw_app_meta_data ->> 'role' in ('admin', 'owner', 'moderator')
      )
  ) then
    raise exception 'admin access required';
  end if;

  return query
  select b.bot_user_id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled, b.created_at
  from public.bots b
  order by b.created_at desc;
end;
$$;

create or replace function public.set_bot_verified(
  p_bot_user_id uuid,
  p_verified boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1
    from auth.users
    where id = auth.uid()
      and (
        raw_user_meta_data ->> 'role' in ('admin', 'owner', 'moderator')
        or raw_app_meta_data ->> 'role' in ('admin', 'owner', 'moderator')
      )
  ) then
    raise exception 'admin access required';
  end if;

  update public.bots
  set is_verified = p_verified, updated_at = now()
  where bot_user_id = p_bot_user_id;
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('bot_verified', p_verified)
  where id = p_bot_user_id;
end;
$$;

alter table public.messages
  add column if not exists bot_inline_keyboard jsonb,
  add column if not exists bot_update_text text,
  add column if not exists bot_plaintext boolean not null default false,
  add column if not exists is_bot_message boolean not null default false;

create table if not exists public.bot_updates (
  id bigint generated always as identity primary key,
  bot_user_id uuid not null references auth.users(id) on delete cascade,
  update_type text not null check (update_type in ('message', 'callback_query')),
  chat_id uuid not null,
  message_id uuid,
  callback_data text,
  text text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists bot_updates_pending_idx
  on public.bot_updates(bot_user_id, id) where processed_at is null;
alter table public.bot_updates enable row level security;
grant select, insert on public.bot_updates to authenticated;
grant all on public.bot_updates to service_role;

drop policy if exists bot_updates_callback_insert on public.bot_updates;
create policy bot_updates_callback_insert on public.bot_updates
  for insert to authenticated
  with check (
    exists (
      select 1 from public.room_participants p
      where p.room_id = chat_id and p.user_id = auth.uid()
    )
    and exists (
      select 1 from public.room_participants p
      join auth.users u on u.id = p.user_id
      where p.room_id = chat_id and p.user_id = bot_user_id
        and coalesce(u.raw_user_meta_data ->> 'is_bot', 'false') = 'true'
    )
  );

drop function if exists public.find_bot_by_token(text);

create function public.find_bot_by_token(p_token_hash text)
returns table (
  bot_user_id uuid,
  owner_id uuid,
  name text,
  tag text,
  description text,
  avatar_url text,
  is_verified boolean,
  is_enabled boolean
)
language sql
security definer
set search_path = public
as $$
  select b.bot_user_id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled
  from public.bots b
  where b.token_hash = p_token_hash and b.is_enabled;
$$;

create or replace function public.enqueue_bot_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bot record;
begin
  for v_bot in
    select p.user_id
    from public.room_participants p
    join auth.users u on u.id = p.user_id
    where p.room_id = new.room_id
      and p.user_id <> new.profile_id
      and coalesce(u.raw_user_meta_data ->> 'is_bot', 'false') = 'true'
  loop
    insert into public.bot_updates (
      bot_user_id, update_type, chat_id, message_id, text, payload
    ) values (
      v_bot.user_id,
      'message',
      new.room_id,
      new.id,
      coalesce(new.bot_update_text, new.encrypted_content),
      jsonb_build_object(
        'message_id', new.id,
        'chat_id', new.room_id,
        'from', jsonb_build_object(
          'id', new.profile_id,
          'name', new.sender_name,
          'tag', new.sender_tag
        ),
        'text', coalesce(new.bot_update_text, new.encrypted_content)
      )
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists enqueue_bot_updates on public.messages;
create trigger enqueue_bot_updates
after insert on public.messages
for each row execute function public.enqueue_bot_update();

grant execute on function public.register_bot(uuid, uuid, text, text, text, text, text) to authenticated;
grant execute on function public.get_my_bots() to authenticated;
grant execute on function public.get_all_bots() to authenticated;
grant execute on function public.set_bot_verified(uuid, boolean) to authenticated;
grant execute on function public.find_bot_by_token(text) to service_role;
