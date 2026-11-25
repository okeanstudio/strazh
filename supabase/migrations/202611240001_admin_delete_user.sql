create or replace function public.delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_support_staff() then
    raise exception 'Only platform admins can delete users'
      using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'User ID is required'
      using errcode = '22004';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Admins cannot delete their own account here'
      using errcode = '42501';
  end if;

  perform 1
  from auth.users
  where id = p_user_id
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = '22023';
  end if;

  perform set_config('app.account_deletion', 'on', true);

  with transferred_rooms as (
    update public.rooms as room
    set created_by = (
      select participant.user_id
      from public.room_participants as participant
      where participant.room_id = room.id
        and participant.user_id <> p_user_id
      order by participant.user_id
      limit 1
    )
    where room.created_by = p_user_id
      and exists (
        select 1
        from public.room_participants as participant
        where participant.room_id = room.id
          and participant.user_id <> p_user_id
      )
    returning room.id, room.created_by
  )
  update public.room_participants as participant
  set role = 'owner'
  from transferred_rooms as transferred
  where participant.room_id = transferred.id
    and participant.user_id = transferred.created_by;

  delete from public.rooms as room
  where room.created_by = p_user_id;

  delete from auth.users
  where id = p_user_id;
end;
$$;

revoke all on function public.delete_user(uuid) from public;
grant execute on function public.delete_user(uuid) to authenticated;

notify pgrst, 'reload schema';
