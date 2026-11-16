create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('technical', 'account', 'payments', 'other')),
  subject text not null,
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_ticket_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_type text not null check (sender_type in ('user', 'support')),
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists support_tickets_user_updated_idx
  on public.support_tickets (user_id, updated_at desc);
create index if not exists support_ticket_messages_ticket_created_idx
  on public.support_ticket_messages (ticket_id, created_at);

create or replace function public.is_support_staff()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '')
      in ('moderator', 'admin', 'owner')
      or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('moderator', 'admin', 'owner');
$$;

revoke all on function public.is_support_staff() from public;
grant execute on function public.is_support_staff() to authenticated;

create or replace function public.touch_support_ticket_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.support_tickets
  set updated_at = new.created_at,
      status = case
        when new.sender_type = 'support' then 'answered'
        else 'open'
      end
  where id = new.ticket_id;
  return new;
end;
$$;

revoke all on function public.touch_support_ticket_from_message() from public;

drop trigger if exists support_ticket_message_updates_ticket
  on public.support_ticket_messages;
create trigger support_ticket_message_updates_ticket
  after insert on public.support_ticket_messages
  for each row execute function public.touch_support_ticket_from_message();

alter table public.support_tickets enable row level security;
alter table public.support_ticket_messages enable row level security;

grant select, insert, update on public.support_tickets to authenticated;
grant select, insert on public.support_ticket_messages to authenticated;

drop policy if exists "Ticket owners and support staff can view tickets"
  on public.support_tickets;
create policy "Ticket owners and support staff can view tickets"
  on public.support_tickets
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_support_staff());

drop policy if exists "Users can create their own tickets"
  on public.support_tickets;
create policy "Users can create their own tickets"
  on public.support_tickets
  for insert
  to authenticated
  with check (user_id = auth.uid() and status = 'open');

drop policy if exists "Support staff can update tickets"
  on public.support_tickets;
create policy "Support staff can update tickets"
  on public.support_tickets
  for update
  to authenticated
  using (public.is_support_staff())
  with check (public.is_support_staff());

drop policy if exists "Ticket owners and support staff can view messages"
  on public.support_ticket_messages;
create policy "Ticket owners and support staff can view messages"
  on public.support_ticket_messages
  for select
  to authenticated
  using (
    public.is_support_staff()
    or exists (
      select 1
      from public.support_tickets as ticket
      where ticket.id = support_ticket_messages.ticket_id
        and ticket.user_id = auth.uid()
    )
  );

drop policy if exists "Users and support staff can reply to tickets"
  on public.support_ticket_messages;
create policy "Users and support staff can reply to tickets"
  on public.support_ticket_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and (
      (
        sender_type = 'user'
        and exists (
          select 1
          from public.support_tickets as ticket
          where ticket.id = support_ticket_messages.ticket_id
            and ticket.user_id = auth.uid()
            and ticket.status <> 'closed'
        )
      )
      or (sender_type = 'support' and public.is_support_staff())
    )
  );

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'support_tickets'
    ) then
      alter publication supabase_realtime add table public.support_tickets;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'support_ticket_messages'
    ) then
      alter publication supabase_realtime add table public.support_ticket_messages;
    end if;
  end if;
end
$$;