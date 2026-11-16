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
    and message.profile_id <> (select auth.uid())
    and message.created_at >= participant.joined_at
    and message_read.message_id is null
  group by message.room_id;
$$;

revoke all on function public.get_unread_message_counts(uuid) from public;
grant execute on function public.get_unread_message_counts(uuid) to authenticated;
