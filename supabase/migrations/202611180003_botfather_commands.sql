alter table public.bots
  alter column owner_id drop not null,
  alter column token_hash drop not null,
  add column if not exists token text,
  add column if not exists is_system boolean not null default false;

insert into public.bots (
  id, owner_id, name, tag, description, token_hash, token, is_verified,
  is_enabled, is_system
)
values (
  '00000000-0000-4000-8000-000000000001',
  null,
  'BotFather',
  'BotFather',
  'Создавайте ботов и управляйте своими ботами командами.',
  null,
  null,
  true,
  true,
  true
)
on conflict (id) do update set
  name = excluded.name,
  tag = excluded.tag,
  description = excluded.description,
  is_verified = true,
  is_enabled = true,
  is_system = true;

revoke select on public.bots from anon, authenticated;
grant select (
  id, owner_id, name, tag, description, avatar_url, token_hash,
  is_verified, is_enabled, is_system, created_at, updated_at
) on public.bots to authenticated;

drop function if exists public.create_bot(text, text, text, text, text);

create function public.create_bot(
  p_name text,
  p_tag text,
  p_description text,
  p_avatar_url text,
  p_token text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
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
     or coalesce(btrim(p_token), '') = '' then
    raise exception 'bot name, tag and token are required';
  end if;
  if v_tag !~ '^[a-z0-9_]{3,32}$' then
    raise exception 'bot tag must contain 3-32 letters, numbers or underscores';
  end if;
  if v_tag !~ 'bot$' then
    raise exception 'bot username must end with bot';
  end if;
  if v_tag = 'botfather' then
    raise exception 'this username is reserved';
  end if;

  insert into public.bots (
    owner_id, name, tag, description, avatar_url, token_hash, token
  ) values (
    auth.uid(),
    btrim(p_name),
    v_tag,
    btrim(coalesce(p_description, '')),
    nullif(btrim(p_avatar_url), ''),
    encode(extensions.digest(convert_to(btrim(p_token), 'UTF8'), 'sha256'), 'hex'),
    btrim(p_token)
  )
  returning id into v_bot_id;

  return v_bot_id;
end;
$$;

create or replace function public.get_my_bot_token(p_bot_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  select token into v_token
  from public.bots
  where id = p_bot_id and owner_id = auth.uid();
  if not found or v_token is null then
    raise exception 'bot not found or access denied';
  end if;
  return v_token;
end;
$$;

create or replace function public.send_botfather_message(p_room_id uuid, p_text text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.room_participants participant
    join public.bot_chat_participants bot_participant
      on bot_participant.room_id = participant.room_id
    join public.bots bot
      on bot.id = bot_participant.bot_id
     and bot.is_system
    where participant.room_id = p_room_id
      and participant.user_id = auth.uid()
      and bot.id = '00000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'BotFather chat access required';
  end if;

  insert into public.messages (
    room_id, profile_id, bot_id, encrypted_content,
    encrypted_content_type, sender_name, sender_tag,
    bot_plaintext, is_bot_message, created_at
  ) values (
    p_room_id,
    auth.uid(),
    '00000000-0000-4000-8000-000000000001',
    p_text,
    'text/plain',
    'BotFather',
    'BotFather',
    true,
    true,
    now()
  )
  returning id into v_message_id;

  return v_message_id;
end;
$$;

drop policy if exists "Bot messages are server-authored" on public.messages;
create policy "Bot messages are server-authored"
  on public.messages
  as restrictive
  for insert
  to authenticated
  with check (bot_id is null);

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
     and not bot.is_system
    where participant.room_id = new.room_id
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

revoke all on function public.create_bot(text, text, text, text, text)
  from public, anon;
revoke all on function public.get_my_bot_token(uuid) from public, anon;
revoke all on function public.send_botfather_message(uuid, text)
  from public, anon;
grant execute on function public.create_bot(text, text, text, text, text)
  to authenticated;
grant execute on function public.get_my_bot_token(uuid) to authenticated;
grant execute on function public.send_botfather_message(uuid, text)
  to authenticated;
