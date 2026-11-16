create or replace function public.get_my_inviter_profile()
returns table(id uuid, name text, tag text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  inviter_id text;
begin
  if auth.uid() is null then
    return;
  end if;

  select raw_user_meta_data ->> 'invited_by_user_id'
  into inviter_id
  from auth.users
  where auth.users.id = auth.uid();

  if inviter_id is null or inviter_id = auth.uid()::text then
    return;
  end if;

  return query
  select
    inviter.id,
    coalesce(nullif(inviter.raw_user_meta_data ->> 'name', ''), 'Без имени'),
    coalesce(inviter.raw_user_meta_data ->> 'tag', '')
  from auth.users as inviter
  where inviter.id::text = inviter_id;
end;
$$;

revoke all on function public.get_my_inviter_profile() from public;
grant execute on function public.get_my_inviter_profile() to authenticated;
