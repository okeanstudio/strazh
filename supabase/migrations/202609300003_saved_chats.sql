create table if not exists public.saved_chats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  room_id uuid not null unique references public.rooms(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.saved_chats enable row level security;

grant select, insert on public.saved_chats to authenticated;

drop policy if exists "Users can view their saved chat"
  on public.saved_chats;
create policy "Users can view their saved chat"
  on public.saved_chats
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users can create their saved chat"
  on public.saved_chats;
create policy "Users can create their saved chat"
  on public.saved_chats
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = saved_chats.room_id
        and participant.user_id = auth.uid()
    )
  );