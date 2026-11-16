do $$
declare
  table_name text;
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'Required publication supabase_realtime does not exist';
  end if;

  foreach table_name in array array[
    'messages',
    'rooms',
    'room_participants',
    'message_reads',
    'phone_login_challenges'
  ]
  loop
    if to_regclass(format('public.%I', table_name)) is not null
      and not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      )
    then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    end if;
  end loop;
end;
$$;

drop policy if exists "Room members can read chat messages for realtime"
  on public.messages;
create policy "Room members can read chat messages for realtime"
  on public.messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.room_participants as participant
      where participant.room_id = messages.room_id
        and participant.user_id = (select auth.uid())
    )
  );

alter table public.messages replica identity full;
