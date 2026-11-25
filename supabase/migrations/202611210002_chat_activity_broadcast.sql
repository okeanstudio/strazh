grant select, insert on table realtime.messages to authenticated;

drop policy if exists "Room members can receive chat activity broadcasts"
  on realtime.messages;
create policy "Room members can receive chat activity broadcasts"
  on realtime.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where 'typing:' || participant.room_id::text = (select realtime.topic())
        and participant.user_id = (select auth.uid())
    )
  );

drop policy if exists "Room members can send chat activity broadcasts"
  on realtime.messages;
create policy "Room members can send chat activity broadcasts"
  on realtime.messages
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.room_participants as participant
      where 'typing:' || participant.room_id::text = (select realtime.topic())
        and participant.user_id = (select auth.uid())
    )
  );
