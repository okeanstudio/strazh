alter table public.bot_updates
  add column if not exists callback_answer_text text,
  add column if not exists callback_answer_show_alert boolean not null default false;

drop policy if exists bot_updates_callback_answer_select
  on public.bot_updates;
create policy bot_updates_callback_answer_select
  on public.bot_updates
  for select
  to authenticated
  using (
    update_type = 'callback_query'
    and actor_id = auth.uid()
  );

alter table public.bot_updates replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'bot_updates'
  ) then
    alter publication supabase_realtime add table public.bot_updates;
  end if;
end;
$$;
