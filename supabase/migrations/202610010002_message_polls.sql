alter table public.messages
  add column if not exists poll_options jsonb not null default '[]'::jsonb;
alter table public.messages
  add column if not exists poll_allow_multiple boolean not null default false;
alter table public.messages
  add column if not exists poll_closed boolean not null default false;

create table if not exists public.message_poll_votes (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_indices integer[] not null,
  updated_at timestamptz not null default now(),
  primary key (message_id, user_id),
  check (cardinality(option_indices) between 1 and 10)
);

create index if not exists message_poll_votes_message_id_idx
  on public.message_poll_votes (message_id);

alter table public.message_poll_votes enable row level security;
grant select, insert, update, delete
  on public.message_poll_votes to authenticated;

drop policy if exists "Room members can view poll votes"
  on public.message_poll_votes;
create policy "Room members can view poll votes"
  on public.message_poll_votes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.messages as message
      join public.room_participants as participant
        on participant.room_id = message.room_id
      where message.id = message_poll_votes.message_id
        and message.encrypted_content_type = 'poll'
        and participant.user_id = auth.uid()
    )
  );

drop policy if exists "Room members can cast poll votes"
  on public.message_poll_votes;
create policy "Room members can cast poll votes"
  on public.message_poll_votes
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.messages as message
      join public.room_participants as participant
        on participant.room_id = message.room_id
      where message.id = message_poll_votes.message_id
        and message.encrypted_content_type = 'poll'
        and not message.poll_closed
        and participant.user_id = auth.uid()
        and (
          message.poll_allow_multiple
          or cardinality(message_poll_votes.option_indices) = 1
        )
        and not exists (
          select 1
          from unnest(message_poll_votes.option_indices) as selected(option_index)
          where selected.option_index < 0
            or selected.option_index >= jsonb_array_length(message.poll_options)
        )
        and cardinality(message_poll_votes.option_indices) = (
          select count(distinct option_index)
          from unnest(message_poll_votes.option_indices) as selected(option_index)
        )
    )
  );

drop policy if exists "Users can update their own poll votes"
  on public.message_poll_votes;
create policy "Users can update their own poll votes"
  on public.message_poll_votes
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
      where message.id = message_poll_votes.message_id
        and message.encrypted_content_type = 'poll'
        and not message.poll_closed
        and participant.user_id = auth.uid()
        and (
          message.poll_allow_multiple
          or cardinality(message_poll_votes.option_indices) = 1
        )
        and not exists (
          select 1
          from unnest(message_poll_votes.option_indices) as selected(option_index)
          where selected.option_index < 0
            or selected.option_index >= jsonb_array_length(message.poll_options)
        )
        and cardinality(message_poll_votes.option_indices) = (
          select count(distinct option_index)
          from unnest(message_poll_votes.option_indices) as selected(option_index)
        )
    )
  );

drop policy if exists "Users can remove their own poll votes"
  on public.message_poll_votes;
create policy "Users can remove their own poll votes"
  on public.message_poll_votes
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
      and tablename = 'message_poll_votes'
  ) then
    alter publication supabase_realtime add table public.message_poll_votes;
  end if;
end
$$;