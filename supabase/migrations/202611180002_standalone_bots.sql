drop trigger if exists enqueue_bot_updates on public.messages;
drop function if exists public.enqueue_bot_update();
drop function if exists public.register_bot(uuid, uuid, text, text, text, text, text);
drop function if exists public.get_my_bots();
drop function if exists public.get_all_bots();
drop function if exists public.set_bot_verified(uuid, boolean);
drop function if exists public.find_bot_by_token(text);

do $$
begin
  if to_regclass('public.bot_chat_participants') is not null then
    delete from public.rooms room
    where room.type = 'direct'
      and exists (
        select 1
        from public.bot_chat_participants participant
        where participant.room_id = room.id
      );
  end if;
end;
$$;

delete from public.rooms room
where room.type = 'direct'
  and exists (
    select 1
    from public.room_participants participant
    where participant.room_id = room.id
      and participant.user_id in (
        select id
        from auth.users
        where raw_user_meta_data ->> 'is_bot' = 'true'
          and email like '%@bots.local'
      )
  );

delete from auth.users
where raw_user_meta_data ->> 'is_bot' = 'true'
  and email like '%@bots.local';

drop table if exists public.bot_updates cascade;
drop table if exists public.bot_chat_participants cascade;
drop table if exists public.bots cascade;

create table public.bots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  tag text not null,
  description text not null default '',
  avatar_url text,
  token_hash text not null unique,
  is_verified boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index bots_tag_unique on public.bots (lower(tag));
create index bots_owner_idx on public.bots (owner_id, created_at desc);
alter table public.bots enable row level security;
grant select on public.bots to authenticated;

create policy bots_public_read on public.bots
  for select to authenticated using (true);

create table public.bot_chat_participants (
  room_id uuid not null references public.rooms(id) on delete cascade,
  bot_id uuid not null references public.bots(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, bot_id)
);
create index bot_chat_participants_bot_idx
  on public.bot_chat_participants(bot_id, room_id);

alter table public.bot_chat_participants enable row level security;
grant select on public.bot_chat_participants to authenticated;
create policy bot_chat_participants_room_member_read
  on public.bot_chat_participants
  for select to authenticated
  using (
    exists (
      select 1
      from public.room_participants participant
      where participant.room_id = bot_chat_participants.room_id
        and participant.user_id = auth.uid()
    )
  );

create or replace function public.create_bot(
  p_name text,
  p_tag text,
  p_description text,
  p_avatar_url text,
  p_token_hash text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_bot_id uuid;
  v_tag text := lower(regexp_replace(trim(p_tag), '^@+', '', 'g'));
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if coalesce(btrim(p_name), '') = ''
     or coalesce(v_tag, '') = ''
     or coalesce(p_token_hash, '') = '' then
    raise exception 'bot name, tag and token are required';
  end if;
  if v_tag !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'bot tag must contain 3-32 letters, numbers or underscores';
  end if;

  insert into public.bots (
    owner_id, name, tag, description, avatar_url, token_hash
  ) values (
    auth.uid(), btrim(p_name), v_tag, btrim(coalesce(p_description, '')),
    nullif(btrim(p_avatar_url), ''), p_token_hash
  )
  returning id into v_bot_id;

  return v_bot_id;
end;
$$;

create or replace function public.add_bot_to_direct_chat(
  p_room_id uuid,
  p_bot_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.room_participants participant
    join public.rooms room on room.id = participant.room_id
    join public.bots bot on bot.id = p_bot_id and bot.is_enabled
    where participant.room_id = p_room_id
      and participant.user_id = auth.uid()
      and room.type = 'direct'
  ) then
    raise exception 'bot can only be added to a direct chat you belong to';
  end if;

  insert into public.bot_chat_participants (room_id, bot_id)
  values (p_room_id, p_bot_id)
  on conflict do nothing;
end;
$$;

create or replace function public.get_my_bots()
returns table (
  id uuid,
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
  select b.id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled, b.created_at
  from public.bots b
  where b.owner_id = auth.uid()
  order by b.created_at desc;
$$;

create or replace function public.get_all_bots()
returns table (
  id uuid,
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
  select b.id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled, b.created_at
  from public.bots b
  order by b.created_at desc;
end;
$$;

create or replace function public.set_bot_verified(p_bot_id uuid, p_verified boolean)
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
  where id = p_bot_id;
end;
$$;

create or replace function public.find_bot_by_token(p_token_hash text)
returns table (
  id uuid,
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
  select b.id, b.owner_id, b.name, b.tag, b.description,
         b.avatar_url, b.is_verified, b.is_enabled
  from public.bots b
  where b.token_hash = p_token_hash and b.is_enabled;
$$;

alter table public.messages
  add column if not exists bot_id uuid references public.bots(id) on delete set null,
  add column if not exists bot_inline_keyboard jsonb,
  add column if not exists bot_update_text text,
  add column if not exists bot_plaintext boolean not null default false,
  add column if not exists is_bot_message boolean not null default false;
create index if not exists messages_bot_id_idx
  on public.messages(bot_id) where bot_id is not null;

create table public.bot_updates (
  id bigint generated always as identity primary key,
  bot_id uuid not null references public.bots(id) on delete cascade,
  update_type text not null check (update_type in ('message', 'callback_query')),
  chat_id uuid not null references public.rooms(id) on delete cascade,
  message_id uuid,
  callback_data text,
  text text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index bot_updates_pending_idx
  on public.bot_updates(bot_id, id) where processed_at is null;
alter table public.bot_updates enable row level security;
grant select, insert on public.bot_updates to authenticated;
grant all on public.bot_updates to service_role;

create policy bot_updates_callback_insert on public.bot_updates
  for insert to authenticated
  with check (
    update_type = 'callback_query'
    and exists (
      select 1
      from public.room_participants participant
      join public.bot_chat_participants bot_participant
        on bot_participant.room_id = participant.room_id
      where participant.room_id = chat_id
        and participant.user_id = auth.uid()
        and bot_participant.bot_id = bot_updates.bot_id
    )
    and exists (
      select 1
      from public.messages message
      where message.id = message_id
        and message.room_id = chat_id
        and message.bot_id = bot_updates.bot_id
    )
  );

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
    select participant.bot_id
    from public.bot_chat_participants participant
    join public.bots bot
      on bot.id = participant.bot_id
     and bot.is_enabled
    where participant.room_id = new.room_id
      and new.bot_id is distinct from participant.bot_id
  loop
    insert into public.bot_updates (
      bot_id, update_type, chat_id, message_id, text, payload
    ) values (
      v_bot.bot_id,
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

create trigger enqueue_bot_updates
after insert on public.messages
for each row execute function public.enqueue_bot_update();

grant execute on function public.create_bot(text, text, text, text, text) to authenticated;
grant execute on function public.add_bot_to_direct_chat(uuid, uuid) to authenticated;
grant execute on function public.get_my_bots() to authenticated;
grant execute on function public.get_all_bots() to authenticated;
grant execute on function public.set_bot_verified(uuid, boolean) to authenticated;
grant execute on function public.find_bot_by_token(text) to service_role;

revoke all on function public.create_bot(text, text, text, text, text) from public, anon;
revoke all on function public.add_bot_to_direct_chat(uuid, uuid) from public, anon;
revoke all on function public.get_my_bots() from public, anon;
revoke all on function public.get_all_bots() from public, anon;
revoke all on function public.set_bot_verified(uuid, boolean) from public, anon;
revoke all on function public.find_bot_by_token(text) from public, anon, authenticated;
grant execute on function public.find_bot_by_token(text) to service_role;

create or replace function public.get_unread_message_counts(
  p_room_id uuid default null
)
returns table(room_id uuid, unread_count bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    message.room_id,
    count(*) as unread_count
  from public.messages as message
  join public.room_participants as participant
    on participant.room_id = message.room_id
   and participant.user_id = (select auth.uid())
  left join public.message_reads as message_read
    on message_read.message_id = message.id
   and message_read.user_id = (select auth.uid())
  where (p_room_id is null or message.room_id = p_room_id)
    and (
      message.bot_id is not null
      or message.profile_id <> (select auth.uid())
    )
    and message.created_at >= participant.joined_at
    and message_read.message_id is null
  group by message.room_id;
$$;
