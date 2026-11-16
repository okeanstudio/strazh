create table if not exists public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid references auth.users(id) on delete set null,
  reported_user_name text not null default ''
    check (char_length(reported_user_name) <= 100),
  target_type text not null check (target_type in ('user', 'message')),
  message_id uuid references public.messages(id) on delete set null,
  chat_id uuid references public.rooms(id) on delete set null,
  content_snapshot text not null default ''
    check (char_length(content_snapshot) <= 2000),
  reason text not null
    check (reason in ('spam', 'harassment', 'inappropriate', 'illegal', 'other')),
  details text not null default '' check (char_length(details) <= 1000),
  status text not null default 'open'
    check (status in ('open', 'reviewing', 'resolved', 'rejected')),
  created_at timestamptz not null default now(),
  constraint moderation_reports_message_required_on_insert
    check (target_type <> 'user' or message_id is null)
);

create index if not exists moderation_reports_status_created_idx
  on public.moderation_reports (status, created_at desc);
create index if not exists moderation_reports_reported_user_idx
  on public.moderation_reports (reported_user_id, created_at desc);

alter table public.moderation_reports enable row level security;

grant select, insert on public.moderation_reports to authenticated;
grant update (status) on public.moderation_reports to authenticated;

drop policy if exists "Reporters and moderators can view reports"
  on public.moderation_reports;
create policy "Reporters and moderators can view reports"
  on public.moderation_reports
  for select
  to authenticated
  using (reporter_id = auth.uid() or public.is_support_staff());

drop policy if exists "Users can submit moderation reports"
  on public.moderation_reports;
create policy "Users can submit moderation reports"
  on public.moderation_reports
  for insert
  to authenticated
  with check (
    reporter_id = auth.uid()
    and reported_user_id is not null
    and reported_user_id <> auth.uid()
    and status = 'open'
    and (
      (
        target_type = 'user'
        and message_id is null
        and content_snapshot = ''
      )
      or (
        target_type = 'message'
        and message_id is not null
        and exists (
          select 1
          from public.messages as message
          where message.id = moderation_reports.message_id
            and message.profile_id = moderation_reports.reported_user_id
            and message.room_id = moderation_reports.chat_id
            and not coalesce(message.sender_is_channel, false)
        )
      )
    )
  );

drop policy if exists "Moderators can update report status"
  on public.moderation_reports;
create policy "Moderators can update report status"
  on public.moderation_reports
  for update
  to authenticated
  using (public.is_support_staff())
  with check (public.is_support_staff());

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'moderation_reports'
  ) then
    alter publication supabase_realtime add table public.moderation_reports;
  end if;
end
$$;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_id uuid := auth.uid();
begin
  if account_id is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  delete from auth.users
  where id = account_id;

  if not found then
    raise exception 'Account not found';
  end if;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
