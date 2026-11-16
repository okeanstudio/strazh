create table if not exists public.email_change_challenges (
  user_id uuid primary key,
  old_email text not null,
  new_email text not null,
  stage text not null check (stage in ('old', 'new')),
  old_code_hash text not null,
  new_code_hash text,
  attempts integer not null default 0 check (attempts >= 0),
  expires_at timestamptz not null,
  last_sent_at timestamptz not null,
  created_at timestamptz not null default now()
);

alter table public.email_change_challenges enable row level security;

revoke all on public.email_change_challenges from anon, authenticated;
grant all on public.email_change_challenges to service_role;
