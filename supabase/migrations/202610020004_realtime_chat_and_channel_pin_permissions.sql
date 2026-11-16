create or replace function public.guard_channel_message_pin_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  room_type text;
  room_owner_id uuid;
  actor_role text;
begin
  if new.is_pinned is not distinct from old.is_pinned then
    return new;
  end if;

  select room.type, room.created_by
  into room_type, room_owner_id
  from public.rooms as room
  where room.id = old.room_id;

  if room_type <> 'channel' then
    return new;
  end if;

  select participant.role
  into actor_role
  from public.room_participants as participant
  where participant.room_id = old.room_id
    and participant.user_id = auth.uid();

  if auth.uid() is distinct from room_owner_id
    and coalesce(actor_role, 'member') not in ('owner', 'admin') then
    raise exception 'Only channel admins can pin or unpin messages'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_channel_message_pin_changes
  on public.messages;
create trigger guard_channel_message_pin_changes
  before update of is_pinned on public.messages
  for each row
  when (old.is_pinned is distinct from new.is_pinned)
  execute function public.guard_channel_message_pin_changes();

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'messages'
    ) then
      alter publication supabase_realtime add table public.messages;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'rooms'
    ) then
      alter publication supabase_realtime add table public.rooms;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'room_participants'
    ) then
      alter publication supabase_realtime add table public.room_participants;
    end if;
  end if;
end;
$$;

alter table public.messages replica identity full;
