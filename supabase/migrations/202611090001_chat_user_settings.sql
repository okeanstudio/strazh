create table if not exists public.chat_user_settings (
  user_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  is_muted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create index if not exists chat_user_settings_muted_room_idx
  on public.chat_user_settings (room_id, user_id)
  where is_muted;

alter table public.chat_user_settings enable row level security;

create policy "Users can view their chat settings"
  on public.chat_user_settings
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = chat_user_settings.room_id
        and participant.user_id = (select auth.uid())
    )
  );

create policy "Users can create their chat settings"
  on public.chat_user_settings
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = chat_user_settings.room_id
        and participant.user_id = (select auth.uid())
    )
  );

create policy "Users can update their chat settings"
  on public.chat_user_settings
  for update
  to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = chat_user_settings.room_id
        and participant.user_id = (select auth.uid())
    )
  )
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = chat_user_settings.room_id
        and participant.user_id = (select auth.uid())
    )
  );

create policy "Users can delete their chat settings"
  on public.chat_user_settings
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = chat_user_settings.room_id
        and participant.user_id = (select auth.uid())
    )
  );

grant select, insert, update, delete
  on public.chat_user_settings
  to authenticated;
