create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null check (char_length(reaction) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists message_reactions_message_id_idx
  on public.message_reactions (message_id);

alter table public.message_reactions enable row level security;

grant select, insert, update, delete
  on public.message_reactions to authenticated;

drop policy if exists "Room members can view message reactions"
  on public.message_reactions;
create policy "Room members can view message reactions"
  on public.message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages as message
      join public.room_participants as participant
        on participant.room_id = message.room_id
      where message.id = message_reactions.message_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Room members can add their own reactions"
  on public.message_reactions;
create policy "Room members can add their own reactions"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.messages as message
      join public.room_participants as participant
        on participant.room_id = message.room_id
      where message.id = message_reactions.message_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Users can change their own message reactions"
  on public.message_reactions;
create policy "Users can change their own message reactions"
  on public.message_reactions
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.messages as message
      join public.room_participants as participant
        on participant.room_id = message.room_id
      where message.id = message_reactions.message_id
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Users can remove their own message reactions"
  on public.message_reactions;
create policy "Users can remove their own message reactions"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = auth.uid());

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end
$$;