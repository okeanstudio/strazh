alter table public.rooms
  add column if not exists is_verified boolean not null default false;

create or replace function public.guard_room_settings_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
begin
  if new.created_by is distinct from old.created_by
    or new.type is distinct from old.type then
    raise exception 'Room ownership and type cannot be changed'
      using errcode = '42501';
  end if;

  if new.is_verified is distinct from old.is_verified
    and current_setting('app.channel_verification_update', true) = 'on' then
    if coalesce(auth.jwt() #>> '{user_metadata,role}', '') not in (
      'moderator',
      'admin',
      'owner'
    ) and coalesce(auth.jwt() #>> '{app_metadata,role}', '') not in (
      'moderator',
      'admin',
      'owner'
    ) then
      raise exception 'Only platform admins can verify channels'
        using errcode = '42501';
    end if;

    return new;
  end if;

  select role
  into actor_role
  from public.room_participants
  where room_id = old.id
    and user_id = auth.uid();

  if auth.uid() is distinct from old.created_by
    and coalesce(actor_role, 'member') not in ('owner', 'admin') then
    raise exception 'Only room admins can change room settings'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create or replace function public.get_channels_for_verification()
returns table (
  id uuid,
  name text,
  tag text,
  avatar_url text,
  is_verified boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() #>> '{user_metadata,role}', '') not in (
    'moderator',
    'admin',
    'owner'
  ) and coalesce(auth.jwt() #>> '{app_metadata,role}', '') not in (
    'moderator',
    'admin',
    'owner'
  ) then
    raise exception 'Only platform admins can verify channels'
      using errcode = '42501';
  end if;

  return query
  select room.id, room.name, room.tag, room.avatar_url, room.is_verified
  from public.rooms as room
  where room.type = 'channel'
  order by room.name;
end;
$$;

create or replace function public.set_channel_verified(
  p_room_id uuid,
  p_is_verified boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() #>> '{user_metadata,role}', '') not in (
    'moderator',
    'admin',
    'owner'
  ) and coalesce(auth.jwt() #>> '{app_metadata,role}', '') not in (
    'moderator',
    'admin',
    'owner'
  ) then
    raise exception 'Only platform admins can verify channels'
      using errcode = '42501';
  end if;

  perform 1
  from public.rooms
  where id = p_room_id
    and type = 'channel';

  if not found then
    raise exception 'Channel not found'
      using errcode = 'P0002';
  end if;

  perform set_config('app.channel_verification_update', 'on', true);

  update public.rooms
  set is_verified = p_is_verified
  where id = p_room_id
    and type = 'channel';
end;
$$;

create or replace function public.get_channel_subscriber_count(p_room_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_is_private boolean;
begin
  select coalesce(room.is_private, false)
  into channel_is_private
  from public.rooms as room
  where room.id = p_room_id
    and room.type = 'channel';

  if not found then
    raise exception 'Channel not found'
      using errcode = 'P0002';
  end if;

  if channel_is_private
    and not exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = p_room_id
        and participant.user_id = auth.uid()
    ) then
    raise exception 'Channel is private'
      using errcode = '42501';
  end if;

  return (
    select count(*)::integer
    from public.room_participants as participant
    where participant.room_id = p_room_id
  );
end;
$$;

revoke all on function public.get_channels_for_verification() from public;
revoke all on function public.set_channel_verified(uuid, boolean) from public;
revoke all on function public.get_channel_subscriber_count(uuid) from public;
grant execute on function public.get_channels_for_verification() to authenticated;
grant execute on function public.set_channel_verified(uuid, boolean) to authenticated;
grant execute on function public.get_channel_subscriber_count(uuid) to authenticated;
