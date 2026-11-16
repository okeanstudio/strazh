alter table public.messages
  add column if not exists forwarded_from_user_id uuid
    references auth.users(id) on delete set null;

alter table public.messages
  add column if not exists forwarded_from_name text;