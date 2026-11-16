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
  if current_setting('app.account_deletion', true) = 'on' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

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

create or replace function public.guard_room_settings_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
begin
  if current_setting('app.account_deletion', true) = 'on' then
    return new;
  end if;

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

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_id uuid := auth.uid();
begin
  if account_id is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  perform set_config('app.account_deletion', 'on', true);

  with transferred_rooms as (
    update public.rooms as room
    set created_by = (
      select participant.user_id
      from public.room_participants as participant
      where participant.room_id = room.id
        and participant.user_id <> account_id
      order by participant.user_id
      limit 1
    )
    where room.created_by = account_id
      and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id = room.id
          and participant.user_id <> account_id
      )
    returning room.id, room.created_by
  )
  update public.room_participants as participant
  set role = 'owner'
  from transferred_rooms as transferred
  where participant.room_id = transferred.id
    and participant.user_id = transferred.created_by;

  delete from public.rooms as room
  where room.created_by = account_id;

  delete from auth.users
  where id = account_id;

  if not found then
    raise exception 'Account not found';
  end if;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
