alter table public.bot_updates
  add column if not exists actor_id uuid references auth.users(id) on delete set null;

drop policy if exists bot_updates_callback_insert on public.bot_updates;
create policy bot_updates_callback_insert on public.bot_updates
  for insert to authenticated
  with check (
    update_type = 'callback_query'
    and actor_id = auth.uid()
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
