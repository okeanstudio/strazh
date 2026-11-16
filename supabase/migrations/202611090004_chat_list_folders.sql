create table if not exists public.chat_list_folders (
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 32),
  created_at timestamptz not null default now(),
  primary key (user_id, name)
);

alter table public.chat_list_folders enable row level security;

create policy "Users can view their chat list folders"
  on public.chat_list_folders
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Users can create their chat list folders"
  on public.chat_list_folders
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users can delete their chat list folders"
  on public.chat_list_folders
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, delete
  on public.chat_list_folders
  to authenticated;

alter table public.chat_user_settings
  add column if not exists folder_name text;
