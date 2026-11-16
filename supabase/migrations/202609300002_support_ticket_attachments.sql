alter table public.support_tickets
  drop constraint if exists support_tickets_category_check;
alter table public.support_tickets
  add constraint support_tickets_category_check
  check (category in ('technical', 'account', 'payments', 'suggestion', 'other'));

alter table public.support_ticket_messages
  add column if not exists attachment_path text;
alter table public.support_ticket_messages
  add column if not exists attachment_name text;
alter table public.support_ticket_messages
  add column if not exists attachment_mime_type text;
alter table public.support_ticket_messages
  add column if not exists attachment_size bigint;

revoke update on public.support_tickets from authenticated;
grant update (status, updated_at)
  on public.support_tickets to authenticated;

drop policy if exists "Ticket owners can close their tickets"
  on public.support_tickets;
create policy "Ticket owners can close their tickets"
  on public.support_tickets
  for update
  to authenticated
  using (user_id = auth.uid() and status <> 'closed')
  with check (user_id = auth.uid() and status = 'closed');

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit
)
values (
  'support-ticket-attachments',
  'support-ticket-attachments',
  false,
  15728640
)
on conflict (id) do update
set public = false,
    file_size_limit = 15728640;

drop policy if exists "Ticket participants can upload attachments"
  on storage.objects;
create policy "Ticket participants can upload attachments"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'support-ticket-attachments'
    and exists (
      select 1
      from public.support_tickets as ticket
      where ticket.id::text = split_part(storage.objects.name, '/', 1)
        and (
          public.is_support_staff()
          or (ticket.user_id = auth.uid() and ticket.status <> 'closed')
        )
    )
  );

drop policy if exists "Ticket participants can view attachments"
  on storage.objects;
create policy "Ticket participants can view attachments"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'support-ticket-attachments'
    and exists (
      select 1
      from public.support_tickets as ticket
      where ticket.id::text = split_part(storage.objects.name, '/', 1)
        and (ticket.user_id = auth.uid() or public.is_support_staff())
    )
  );