create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.scheduled_chat_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  message_kind text not null check (message_kind in ('text', 'gift')),
  payload jsonb not null default '{}'::jsonb,
  scheduled_for timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'sending', 'sent', 'failed')),
  message_id uuid references public.messages(id) on delete set null,
  failure_reason text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  constraint scheduled_chat_message_payload_object
    check (jsonb_typeof(payload) = 'object')
);

create index if not exists scheduled_chat_messages_due_idx
  on public.scheduled_chat_messages (scheduled_for, created_at)
  where status = 'pending';
create index if not exists scheduled_chat_messages_sender_idx
  on public.scheduled_chat_messages (sender_id, scheduled_for desc);

alter table public.scheduled_chat_messages enable row level security;
grant select, delete on public.scheduled_chat_messages to authenticated;

drop policy if exists "Users can view their scheduled chat messages"
  on public.scheduled_chat_messages;
create policy "Users can view their scheduled chat messages"
  on public.scheduled_chat_messages
  for select
  to authenticated
  using (sender_id = (select auth.uid()));

drop policy if exists "Users can cancel their pending scheduled chat messages"
  on public.scheduled_chat_messages;
create policy "Users can cancel their pending scheduled chat messages"
  on public.scheduled_chat_messages
  for delete
  to authenticated
  using (
    sender_id = (select auth.uid())
    and status = 'pending'
  );

create or replace function public.schedule_chat_text_message(
  p_room_id uuid,
  p_payload jsonb,
  p_scheduled_for timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  scheduled_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_scheduled_for < now() + interval '30 seconds'
     or p_scheduled_for > now() + interval '1 year' then
    raise exception 'Scheduled time must be between 30 seconds and 1 year from now'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_payload) <> 'object'
     or p_payload ->> 'encrypted_content_type' <> 'text/plain'
     or coalesce(p_payload ->> 'encrypted_content', '') = ''
     or exists (
       select 1
       from jsonb_object_keys(p_payload) as keys(key)
       where key not in (
         'encrypted_content',
         'encrypted_content_type',
         'reply_to_id',
         'reply_to_content',
         'reply_to_sender'
       )
     ) then
    raise exception 'Invalid scheduled text message payload'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.room_participants as participant
    where participant.room_id = p_room_id
      and participant.user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this chat'
      using errcode = '42501';
  end if;

  insert into public.scheduled_chat_messages (
    sender_id,
    room_id,
    message_kind,
    payload,
    scheduled_for
  )
  values (
    auth.uid(),
    p_room_id,
    'text',
    p_payload,
    p_scheduled_for
  )
  returning id into scheduled_message_id;

  return scheduled_message_id;
end;
$$;

create or replace function public.schedule_chat_gift(
  p_room_id uuid,
  p_gift_id text,
  p_caption text,
  p_scheduled_for timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  scheduled_message_id uuid;
  gift_price integer;
  sender_balance bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_scheduled_for < now() + interval '30 seconds'
     or p_scheduled_for > now() + interval '1 year' then
    raise exception 'Scheduled time must be between 30 seconds and 1 year from now'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.rooms
    where id = p_room_id
      and type = 'direct'
  ) or not exists (
    select 1
    from public.room_participants
    where room_id = p_room_id
      and user_id = auth.uid()
  ) then
    raise exception 'Gifts can only be scheduled in a direct chat'
      using errcode = '42501';
  end if;

  select price_enc into gift_price
  from public.gift_catalog
  where id = p_gift_id
    and is_active;
  if gift_price is null then
    raise exception 'Gift is not available' using errcode = '22023';
  end if;

  select coalesce((raw_user_meta_data ->> 'encoins')::bigint, 0)
    into sender_balance
  from auth.users
  where id = auth.uid();
  if sender_balance < gift_price then
    raise exception 'Insufficient Encoins' using errcode = '22023';
  end if;

  insert into public.scheduled_chat_messages (
    sender_id,
    room_id,
    message_kind,
    payload,
    scheduled_for
  )
  values (
    auth.uid(),
    p_room_id,
    'gift',
    jsonb_build_object(
      'gift_id', p_gift_id,
      'caption', left(coalesce(trim(p_caption), ''), 120)
    ),
    p_scheduled_for
  )
  returning id into scheduled_message_id;

  return scheduled_message_id;
end;
$$;

create or replace function public.deliver_scheduled_chat_messages()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  scheduled_message public.scheduled_chat_messages%rowtype;
  sender_metadata jsonb;
  inserted_message_id uuid;
  gift_result jsonb;
  delivered_count integer := 0;
  failure text;
begin
  for scheduled_message in
    select *
    from public.scheduled_chat_messages
    where status = 'pending'
      and scheduled_for <= now()
    order by scheduled_for, created_at
    for update skip locked
    limit 50
  loop
    update public.scheduled_chat_messages
    set status = 'sending',
        failure_reason = null
    where id = scheduled_message.id;

    begin
      if scheduled_message.message_kind = 'gift' then
        perform set_config(
          'request.jwt.claim.sub',
          scheduled_message.sender_id::text,
          true
        );
        perform set_config(
          'request.jwt.claims',
          jsonb_build_object('sub', scheduled_message.sender_id)::text,
          true
        );
        gift_result := public.send_gift(
          scheduled_message.room_id,
          scheduled_message.payload ->> 'gift_id',
          scheduled_message.payload ->> 'caption'
        );
        inserted_message_id := (gift_result ->> 'message_id')::uuid;
      else
        select raw_user_meta_data
          into sender_metadata
        from auth.users
        where id = scheduled_message.sender_id;

        insert into public.messages (
          room_id,
          profile_id,
          sender_name,
          sender_tag,
          sender_avatar,
          encrypted_content,
          encrypted_content_type,
          reply_to_id,
          reply_to_content,
          reply_to_sender,
          created_at
        )
        values (
          scheduled_message.room_id,
          scheduled_message.sender_id,
          coalesce(sender_metadata ->> 'name', sender_metadata ->> 'full_name', 'Пользователь'),
          coalesce(sender_metadata ->> 'tag', ''),
          sender_metadata ->> 'avatar_url',
          scheduled_message.payload ->> 'encrypted_content',
          'text/plain',
          nullif(scheduled_message.payload ->> 'reply_to_id', '')::uuid,
          scheduled_message.payload ->> 'reply_to_content',
          scheduled_message.payload ->> 'reply_to_sender',
          now()
        )
        returning id into inserted_message_id;
      end if;

      update public.scheduled_chat_messages
      set status = 'sent',
          message_id = inserted_message_id,
          delivered_at = now()
      where id = scheduled_message.id;
      delivered_count := delivered_count + 1;
    exception when others then
      get stacked diagnostics failure = message_text;
      update public.scheduled_chat_messages
      set status = 'failed',
          failure_reason = left(failure, 500)
      where id = scheduled_message.id;
    end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  return delivered_count;
end;
$$;

revoke all on function public.schedule_chat_text_message(uuid, jsonb, timestamptz)
  from public;
grant execute on function public.schedule_chat_text_message(uuid, jsonb, timestamptz)
  to authenticated;
revoke all on function public.schedule_chat_gift(uuid, text, text, timestamptz)
  from public;
grant execute on function public.schedule_chat_gift(uuid, text, text, timestamptz)
  to authenticated;
revoke all on function public.deliver_scheduled_chat_messages()
  from public, anon, authenticated;

do $$
declare
  existing_job record;
begin
  for existing_job in
    select jobid
    from cron.job
    where jobname = 'deliver-scheduled-chat-messages'
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;

  perform cron.schedule(
    'deliver-scheduled-chat-messages',
    '* * * * *',
    'select public.deliver_scheduled_chat_messages()'
  );
end;
$$;

alter table public.messages
  add column if not exists view_once boolean not null default false;

create table if not exists public.message_media_views (
  message_id uuid not null references public.messages(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (message_id, viewer_id)
);

alter table public.message_media_views enable row level security;
grant select on public.message_media_views to authenticated;

drop policy if exists "Users can view their own one-time media views"
  on public.message_media_views;
create policy "Users can view their own one-time media views"
  on public.message_media_views
  for select
  to authenticated
  using (viewer_id = (select auth.uid()));

create or replace function public.claim_view_once_message(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  message_record public.messages%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
    into message_record
  from public.messages
  where id = p_message_id
    and view_once
  for update;

  if not found then
    return false;
  end if;

  if not (
    coalesce(message_record.is_image, false)
    or coalesce(message_record.is_voice, false)
    or (
      coalesce(message_record.is_file, false)
      and (
        message_record.encrypted_content_type = 'video_note'
        or lower(coalesce(message_record.file_mime_type, '')) like 'video/%'
      )
    )
  ) then
    raise exception 'One-time viewing is only available for photos, videos and voice messages'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.room_participants
    where room_id = message_record.room_id
      and user_id = auth.uid()
  ) and not exists (
    select 1
    from public.rooms
    where id = message_record.room_id
      and type = 'channel'
      and not coalesce(is_private, false)
  ) then
    raise exception 'You are not a member of this chat'
      using errcode = '42501';
  end if;

  insert into public.message_media_views (message_id, viewer_id)
  values (p_message_id, auth.uid())
  on conflict do nothing;

  return found;
end;
$$;

revoke all on function public.claim_view_once_message(uuid) from public;
grant execute on function public.claim_view_once_message(uuid) to authenticated;

drop policy if exists "One-time chat media requires an active view"
  on storage.objects;
create policy "One-time chat media requires an active view"
  on storage.objects
  as restrictive
  for select
  to public
  using (
    bucket_id not in ('chat_media', 'chat_files', 'voice_messages')
    or not exists (
      select 1
      from public.messages as message
      where message.view_once
        and message.profile_id <> (select auth.uid())
        and (
          message.file_url = storage.objects.name
          or right(message.file_url, length(storage.objects.name))
            = storage.objects.name
          or message.voice_url = storage.objects.name
          or right(message.voice_url, length(storage.objects.name))
            = storage.objects.name
          or message.encrypted_content = storage.objects.name
          or right(message.encrypted_content, length(storage.objects.name))
            = storage.objects.name
        )
        and not exists (
          select 1
          from public.message_media_views as media_view
          where media_view.message_id = message.id
            and media_view.viewer_id = (select auth.uid())
            and media_view.viewed_at > now() - interval '30 seconds'
        )
    )
  );
