create or replace function public.get_all_bots()
returns table (
  id uuid,
  owner_id uuid,
  name text,
  tag text,
  description text,
  avatar_url text,
  is_verified boolean,
  is_enabled boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = auth.uid()
      and (
        auth_user.raw_user_meta_data ->> 'role'
          in ('admin', 'owner', 'moderator')
        or auth_user.raw_app_meta_data ->> 'role'
          in ('admin', 'owner', 'moderator')
      )
  ) then
    raise exception 'admin access required';
  end if;

  return query
  select bot.id, bot.owner_id, bot.name, bot.tag, bot.description,
         bot.avatar_url, bot.is_verified, bot.is_enabled, bot.created_at
  from public.bots as bot
  order by bot.created_at desc;
end;
$$;

revoke all on function public.get_all_bots() from public, anon;
grant execute on function public.get_all_bots() to authenticated;
