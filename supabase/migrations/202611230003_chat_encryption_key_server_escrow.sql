create table if not exists public.chat_encryption_key_escrow (
  user_id uuid primary key references auth.users(id) on delete cascade,
  device_keys jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

comment on table public.chat_encryption_key_escrow is
  'Server-side recovery escrow for E2EE device private keys; accessible only to the account owner.';

alter table public.chat_encryption_key_escrow enable row level security;

drop policy if exists "Users can view their chat encryption key escrow"
  on public.chat_encryption_key_escrow;
create policy "Users can view their chat encryption key escrow"
  on public.chat_encryption_key_escrow
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can create their chat encryption key escrow"
  on public.chat_encryption_key_escrow;
create policy "Users can create their chat encryption key escrow"
  on public.chat_encryption_key_escrow
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can update their chat encryption key escrow"
  on public.chat_encryption_key_escrow;
create policy "Users can update their chat encryption key escrow"
  on public.chat_encryption_key_escrow
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update
  on public.chat_encryption_key_escrow
  to authenticated;
