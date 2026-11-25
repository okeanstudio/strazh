create or replace function public.can_read_profile_music_path(p_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from auth.users as profile_owner
      where profile_owner.raw_user_meta_data ->> 'profile_music_path' = p_path
        and public.can_view_profile_music(profile_owner.id)
    );
$$;

revoke all on function public.can_read_profile_music_path(text) from public;
grant execute on function public.can_read_profile_music_path(text)
  to authenticated;
