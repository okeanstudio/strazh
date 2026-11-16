create or replace function public.get_user_by_tag_ci(p_tag text)
returns table(id uuid, email text)
language sql
stable
security definer
set search_path = ''
as $$
  select auth_user.id, auth_user.email
  from auth.users as auth_user
  where lower(auth_user.raw_user_meta_data ->> 'tag') =
        lower(btrim(coalesce(p_tag, '')))
  limit 1;
$$;

revoke all on function public.get_user_by_tag_ci(text) from public;
grant execute on function public.get_user_by_tag_ci(text) to anon, authenticated;
