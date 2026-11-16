alter table public.room_participants
  add column if not exists role text not null default 'member';

update public.room_participants as participant
set role = 'owner'
from public.rooms as room
where room.id = participant.room_id
  and room.created_by = participant.user_id
  and room.type in ('group', 'channel');

drop trigger if exists guard_private_group_membership
  on public.room_participants;
drop function if exists public.guard_private_group_membership();

create or replace function public.guard_room_participant_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  room_is_private boolean;
  actor_role text;
begin
  if tg_op = 'DELETE' then
    select created_by
    into owner_id
    from public.rooms
    where id = old.room_id;

    if not found then
      return old;
    end if;

    if old.user_id = auth.uid() then
      return old;
    end if;

    select role
    into actor_role
    from public.room_participants
    where room_id = old.room_id
      and user_id = auth.uid();

    if auth.uid() is distinct from owner_id
      and coalesce(actor_role, 'member') not in ('owner', 'admin') then
      raise exception 'Only room admins can remove participants'
        using errcode = '42501';
    end if;

    if old.role = 'owner' and auth.uid() is distinct from owner_id then
      raise exception 'The room owner cannot be removed by an admin'
        using errcode = '42501';
    end if;

    return old;
  end if;

  select created_by, coalesce(is_private, false)
  into owner_id, room_is_private
  from public.rooms
  where id = new.room_id;

  if tg_op = 'INSERT' then
    if new.user_id = owner_id then
      new.role := 'owner';
    else
      new.role := 'member';
    end if;

    select role
    into actor_role
    from public.room_participants
    where room_id = new.room_id
      and user_id = auth.uid();

    if room_is_private
      and new.user_id is distinct from owner_id
      and auth.uid() is distinct from owner_id
      and coalesce(actor_role, 'member') not in ('owner', 'admin') then
      raise exception 'Private rooms can only be joined by invitation'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if new.room_id is distinct from old.room_id
    or new.user_id is distinct from old.user_id then
    raise exception 'Room membership identity cannot be changed'
      using errcode = '42501';
  end if;

  if new.role is distinct from old.role then
    if auth.uid() is distinct from owner_id
      or old.role = 'owner'
      or new.role not in ('admin', 'member') then
      raise exception 'Only the room owner can assign admins'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

create trigger guard_room_participant_changes
  before insert or update or delete on public.room_participants
  for each row execute function public.guard_room_participant_changes();

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

drop trigger if exists guard_room_settings_changes on public.rooms;
create trigger guard_room_settings_changes
  before update on public.rooms
  for each row execute function public.guard_room_settings_changes();

create or replace function public.guard_channel_message_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  room_type text;
begin
  select type
  into room_type
  from public.rooms
  where id = new.room_id;

  if room_type = 'channel'
    and (
      new.profile_id is distinct from auth.uid()
      or not exists (
        select 1
        from public.room_participants as participant
        where participant.room_id = new.room_id
          and participant.user_id = auth.uid()
          and participant.role in ('owner', 'admin')
      )
    ) then
    raise exception 'Only channel admins can publish messages'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_channel_message_author on public.messages;
create trigger guard_channel_message_author
  before insert on public.messages
  for each row execute function public.guard_channel_message_author();

drop policy if exists "Anyone can read public channel messages"
  on public.messages;
create policy "Anyone can read public channel messages"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.rooms as room
      where room.id = messages.room_id
        and room.type = 'channel'
        and not coalesce(room.is_private, false)
    )
  );

create or replace function public.add_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  actor_role text;
begin
  select created_by
  into owner_id
  from public.rooms
  where id = p_room_id;

  select role
  into actor_role
  from public.room_participants
  where room_id = p_room_id
    and user_id = auth.uid();

  if auth.uid() is distinct from owner_id
    and coalesce(actor_role, 'member') not in ('owner', 'admin') then
    raise exception 'Only room admins can add participants'
      using errcode = '42501';
  end if;

  insert into public.room_participants (room_id, user_id)
  values (p_room_id, p_user_id)
  on conflict (room_id, user_id) do nothing;
end;
$$;

create or replace function public.remove_room_member(
  p_room_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  actor_role text;
  target_role text;
begin
  select created_by
  into owner_id
  from public.rooms
  where id = p_room_id;

  select role
  into actor_role
  from public.room_participants
  where room_id = p_room_id
    and user_id = auth.uid();

  select role
  into target_role
  from public.room_participants
  where room_id = p_room_id
    and user_id = p_user_id;

  if p_user_id is distinct from auth.uid()
    and auth.uid() is distinct from owner_id
    and coalesce(actor_role, 'member') not in ('owner', 'admin') then
    raise exception 'Only room admins can remove participants'
      using errcode = '42501';
  end if;

  if target_role = 'owner' and auth.uid() is distinct from owner_id then
    raise exception 'The room owner cannot be removed by an admin'
      using errcode = '42501';
  end if;

  delete from public.room_participants
  where room_id = p_room_id
    and user_id = p_user_id;
end;
$$;

create or replace function public.set_room_member_role(
  p_room_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
begin
  if p_role is null or p_role not in ('admin', 'member') then
    raise exception 'Unsupported room role'
      using errcode = '22023';
  end if;

  select created_by
  into owner_id
  from public.rooms
  where id = p_room_id;

  if auth.uid() is distinct from owner_id then
    raise exception 'Only the room owner can assign admins'
      using errcode = '42501';
  end if;

  update public.room_participants
  set role = p_role
  where room_id = p_room_id
    and user_id = p_user_id
    and role <> 'owner';

  if not found then
    raise exception 'Room participant was not found'
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.update_room_settings(
  p_room_id uuid,
  p_name text,
  p_tag text,
  p_description text,
  p_is_private boolean,
  p_avatar_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_id uuid;
  actor_role text;
begin
  select created_by
  into owner_id
  from public.rooms
  where id = p_room_id;

  select role
  into actor_role
  from public.room_participants
  where room_id = p_room_id
    and user_id = auth.uid();

  if auth.uid() is distinct from owner_id
    and coalesce(actor_role, 'member') not in ('owner', 'admin') then
    raise exception 'Only room admins can change room settings'
      using errcode = '42501';
  end if;

  update public.rooms
  set name = p_name,
      tag = case when p_is_private then null else p_tag end,
      description = p_description,
      is_private = p_is_private,
      avatar_url = p_avatar_url,
      updated_at = now()
  where id = p_room_id;
end;
$$;

revoke all on function public.add_room_member(uuid, uuid) from public;
revoke all on function public.remove_room_member(uuid, uuid) from public;
revoke all on function public.set_room_member_role(uuid, uuid, text) from public;
revoke all on function public.update_room_settings(uuid, text, text, text, boolean, text) from public;
grant execute on function public.add_room_member(uuid, uuid) to authenticated;
grant execute on function public.remove_room_member(uuid, uuid) to authenticated;
grant execute on function public.set_room_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.update_room_settings(uuid, text, text, text, boolean, text) to authenticated;