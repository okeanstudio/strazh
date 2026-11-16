create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null default 'mobile',
  updated_at timestamptz not null default now()
);

alter table public.user_devices enable row level security;
revoke all on public.user_devices from anon, authenticated;

drop policy if exists "Users can register their own devices"
  on public.user_devices;
create policy "Users can register their own devices"
  on public.user_devices
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update their own devices"
  on public.user_devices;
create policy "Users can update their own devices"
  on public.user_devices
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users can delete their own devices"
  on public.user_devices;
create policy "Users can delete their own devices"
  on public.user_devices
  for delete
  to authenticated
  using (user_id = auth.uid());

grant insert, update, delete on public.user_devices to authenticated;
grant all on public.user_devices to service_role;
