create table if not exists public.chat_encryption_key_vault (
  user_id uuid primary key references auth.users(id) on delete cascade,
  salt text not null,
  nonce text not null,
  ciphertext text not null,
  mac text not null,
  updated_at timestamptz not null default now()
);

alter table public.chat_encryption_key_vault enable row level security;

drop policy if exists "Users can view their encrypted chat key vault"
  on public.chat_encryption_key_vault;
create policy "Users can view their encrypted chat key vault"
  on public.chat_encryption_key_vault
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users can create their encrypted chat key vault"
  on public.chat_encryption_key_vault;
create policy "Users can create their encrypted chat key vault"
  on public.chat_encryption_key_vault
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can update their encrypted chat key vault"
  on public.chat_encryption_key_vault;
create policy "Users can update their encrypted chat key vault"
  on public.chat_encryption_key_vault
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update
  on public.chat_encryption_key_vault
  to authenticated;

do $$
begin
  alter publication supabase_realtime
    add table public.chat_encryption_key_vault;
exception
  when duplicate_object then null;
end
$$;
