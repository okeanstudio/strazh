create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists message_reads_room_id_message_id_idx
  on public.message_reads (room_id, message_id);

alter table public.message_reads enable row level security;

drop policy if exists "Room members can view message reads"
  on public.message_reads;
create policy "Room members can view message reads"
  on public.message_reads
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = message_reads.room_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Members can mark other messages read"
  on public.message_reads;
create policy "Members can mark other messages read"
  on public.message_reads
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = message_reads.room_id
        and participant.user_id = auth.uid()
    )
    and exists (
      select 1
      from public.messages as message
      where message.id = message_reads.message_id
        and message.room_id = message_reads.room_id
        and message.profile_id <> auth.uid()
    )
  );

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reads'
  ) then
    alter publication supabase_realtime add table public.message_reads;
  end if;
end
$$;
