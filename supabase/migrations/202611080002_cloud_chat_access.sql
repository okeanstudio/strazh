drop function if exists public.claim_e2ee_prekey(uuid, uuid, text);
drop table if exists public.e2ee_devices;

alter table public.messages enable row level security;
grant select, insert, update, delete on public.messages to authenticated;

drop policy if exists "Room members can read chat messages for realtime"
  on public.messages;
drop policy if exists "Cloud chat members can read messages"
  on public.messages;
drop policy if exists "Cloud chat access is restricted to members"
  on public.messages;
create policy "Cloud chat members can read messages"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.rooms as room
      where room.id = messages.room_id
        and room.type = 'channel'
        and not coalesce(room.is_private, false)
    )
  );

create policy "Cloud chat access is restricted to members"
  on public.messages
  as restrictive
  for select
  to public
  using (
    auth.uid() is not null
    and (
      exists (
        select 1
        from public.room_participants as participant
        where participant.room_id = messages.room_id
          and participant.user_id = auth.uid()
      )
      or exists (
        select 1
        from public.rooms as room
        where room.id = messages.room_id
          and room.type = 'channel'
          and not coalesce(room.is_private, false)
      )
    )
  );

drop policy if exists "Cloud chat members can insert their own messages"
  on public.messages;
create policy "Cloud chat members can insert their own messages"
  on public.messages
  for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Cloud chat inserts require membership"
  on public.messages;
create policy "Cloud chat inserts require membership"
  on public.messages
  as restrictive
  for insert
  to public
  with check (
    auth.uid() is not null
    and profile_id = auth.uid()
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Cloud chat members can update authorized messages"
  on public.messages;
create policy "Cloud chat members can update authorized messages"
  on public.messages
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  )
  with check (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  );

drop policy if exists "Cloud chat updates require membership and authorship"
  on public.messages;
create policy "Cloud chat updates require membership and authorship"
  on public.messages
  as restrictive
  for update
  to public
  using (
    auth.uid() is not null
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  )
  with check (
    auth.uid() is not null
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  );

drop policy if exists "Cloud chat members can delete authorized messages"
  on public.messages;
create policy "Cloud chat members can delete authorized messages"
  on public.messages
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  );

drop policy if exists "Cloud chat deletes require membership and authorship"
  on public.messages;
create policy "Cloud chat deletes require membership and authorship"
  on public.messages
  as restrictive
  for delete
  to public
  using (
    auth.uid() is not null
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = auth.uid()
        and (
          messages.profile_id = auth.uid()
          or participant.role in ('owner', 'admin')
        )
    )
  );

insert into storage.buckets (id, name, public)
values
  ('chat_media', 'chat_media', false),
  ('chat_files', 'chat_files', false),
  ('voice_messages', 'voice_messages', false)
on conflict (id) do update
set public = false;

grant select, insert, update, delete on storage.objects to authenticated;

drop policy if exists "Cloud attachment access is restricted"
  on storage.objects;
create policy "Cloud attachment access is restricted"
  on storage.objects
  as restrictive
  for all
  to public
  using (
    bucket_id not in ('chat_media', 'chat_files', 'voice_messages')
    or (
      auth.uid() is not null
      and (
        exists (
          select 1
          from public.room_participants as participant
          where participant.room_id::text = (storage.foldername(name))[1]
            and participant.user_id = auth.uid()
        )
        or exists (
          select 1
          from public.messages as message
          join public.rooms as room on room.id = message.room_id
          where (
              exists (
                select 1
                from public.room_participants as participant
                where participant.room_id = message.room_id
                  and participant.user_id = auth.uid()
              )
              or (
                room.type = 'channel'
                and not coalesce(room.is_private, false)
              )
            )
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
        )
      )
    )
  )
  with check (
    bucket_id not in ('chat_media', 'chat_files', 'voice_messages')
    or (
      auth.uid() is not null
      and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id::text = (storage.foldername(name))[1]
          and participant.user_id = auth.uid()
      )
    )
  );

drop policy if exists "Chat participants can read chat attachments"
  on storage.objects;
create policy "Chat participants can read chat attachments"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id in ('chat_media', 'chat_files', 'voice_messages')
    and (
        exists (
          select 1
          from public.room_participants as participant
          where participant.room_id::text = (storage.foldername(name))[1]
            and participant.user_id = auth.uid()
        )
        or exists (
          select 1
          from public.messages as message
          join public.rooms as room on room.id = message.room_id
          where (
              exists (
                select 1
                from public.room_participants as participant
                where participant.room_id = message.room_id
                  and participant.user_id = auth.uid()
              )
              or (
                room.type = 'channel'
                and not coalesce(room.is_private, false)
              )
            )
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
        )
    )
  );

drop policy if exists "Chat participants can upload chat attachments"
  on storage.objects;
create policy "Chat participants can upload chat attachments"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id in ('chat_media', 'chat_files', 'voice_messages')
    and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id::text = (storage.foldername(name))[1]
          and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Chat participants can update chat attachments"
  on storage.objects;
create policy "Chat participants can update chat attachments"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id in ('chat_media', 'chat_files', 'voice_messages')
    and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id::text = (storage.foldername(name))[1]
          and participant.user_id = auth.uid()
    )
  )
  with check (
    bucket_id in ('chat_media', 'chat_files', 'voice_messages')
    and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id::text = (storage.foldername(name))[1]
          and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Chat participants can delete chat attachments"
  on storage.objects;
create policy "Chat participants can delete chat attachments"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id in ('chat_media', 'chat_files', 'voice_messages')
    and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id::text = (storage.foldername(name))[1]
          and participant.user_id = auth.uid()
    )
  );
