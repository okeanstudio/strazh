alter table public.privacy_settings
  add column if not exists show_profile_music boolean not null default true;

create or replace function public.can_view_profile_music(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id = (select auth.uid())
    or coalesce(
      (
        select settings.show_profile_music
        from public.privacy_settings as settings
        where settings.user_id = p_user_id
      ),
      true
    );
$$;

revoke all on function public.can_view_profile_music(uuid) from public;
grant execute on function public.can_view_profile_music(uuid) to authenticated;
