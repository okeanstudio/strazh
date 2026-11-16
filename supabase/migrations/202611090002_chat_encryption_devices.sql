create table if not exists public.chat_encryption_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  public_key text not null
    check (octet_length(decode(public_key, 'base64')) = 32),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.chat_encryption_devices enable row level security;

drop policy if exists "Users can view encryption keys in their chats"
  on public.chat_encryption_devices;
create policy "Users can view encryption keys in their chats"
  on public.chat_encryption_devices
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.room_participants as current_participant
      join public.room_participants as target_participant
        on target_participant.room_id = current_participant.room_id
      where current_participant.user_id = (select auth.uid())
        and target_participant.user_id = chat_encryption_devices.user_id
    )
  );

drop policy if exists "Users can register their encryption devices"
  on public.chat_encryption_devices;
create policy "Users can register their encryption devices"
  on public.chat_encryption_devices
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can update their encryption devices"
  on public.chat_encryption_devices;
create policy "Users can update their encryption devices"
  on public.chat_encryption_devices
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can remove their encryption devices"
  on public.chat_encryption_devices;
create policy "Users can remove their encryption devices"
  on public.chat_encryption_devices
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, update, delete
  on public.chat_encryption_devices
  to authenticated;
