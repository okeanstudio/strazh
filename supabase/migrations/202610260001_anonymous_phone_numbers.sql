create table if not exists public.anonymous_phone_numbers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phone_number text not null unique,
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  purchased_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint anonymous_phone_numbers_format
    check (phone_number ~ '^\+888[0-9]{6,14}$')
);

create index if not exists anonymous_phone_numbers_user_id_idx
  on public.anonymous_phone_numbers (user_id);

alter table public.anonymous_phone_numbers enable row level security;

revoke all on table public.anonymous_phone_numbers from anon, authenticated;
grant select on table public.anonymous_phone_numbers to authenticated;
grant all on table public.anonymous_phone_numbers to service_role;

drop policy if exists "Users can view their own anonymous numbers"
  on public.anonymous_phone_numbers;
create policy "Users can view their own anonymous numbers"
  on public.anonymous_phone_numbers
  for select
  to authenticated
  using (user_id = (select auth.uid()));
