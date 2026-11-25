update public.bot_updates as bot_update
set processed_at = now()
from public.messages as message
where bot_update.processed_at is null
  and bot_update.update_type = 'message'
  and bot_update.message_id = message.id
  and bot_update.bot_id = message.bot_id;

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
