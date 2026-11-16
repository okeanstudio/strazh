create table if not exists public.privacy_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  who_can_add_to_groups text not null default 'everyone',
  who_can_send_messages text not null default 'everyone',
  show_phone boolean not null default false,
  show_email boolean not null default false,
  show_status boolean not null default true,
  show_last_seen boolean not null default true,
  show_profile_picture boolean not null default true,
  block_unknown boolean not null default false,
  phone text,
  hide_expired_stories boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.privacy_settings
  add column if not exists hide_expired_stories boolean not null default false;

alter table public.privacy_settings enable row level security;

drop policy if exists "Users can view their privacy settings"
  on public.privacy_settings;
create policy "Users can view their privacy settings"
  on public.privacy_settings
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can create their privacy settings"
  on public.privacy_settings;
create policy "Users can create their privacy settings"
  on public.privacy_settings
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can update their privacy settings"
  on public.privacy_settings;
create policy "Users can update their privacy settings"
  on public.privacy_settings
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update on public.privacy_settings to authenticated;

create or replace function public.can_view_story_archive(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not coalesce(
    (
      select settings.hide_expired_stories
      from public.privacy_settings as settings
      where settings.user_id = p_user_id
    ),
    false
  );
$$;

revoke all on function public.can_view_story_archive(uuid) from public;
grant execute on function public.can_view_story_archive(uuid) to authenticated;

drop policy if exists "Authenticated users can view all stories"
  on public.stories;
create policy "Authenticated users can view visible stories"
  on public.stories
  for select
  to authenticated
  using (
    expires_at > now()
    or public.can_view_story_archive(user_id)
  );

drop policy if exists "Users can view story photos"
  on storage.objects;
create policy "Users can view visible story photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'stories'
    and exists (
      select 1
      from public.stories as story
      where story.image_url = storage.objects.name
    )
  );
