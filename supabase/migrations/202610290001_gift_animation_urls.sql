alter table public.gift_catalog
  add column if not exists animation_url text;

alter table public.messages
  add column if not exists gift_id text
    references public.gift_catalog(id) on delete set null;

update public.messages as message
set gift_id = inventory.gift_id
from public.user_gift_inventory as inventory
where inventory.message_id = message.id
  and message.gift_id is null;

create or replace function public.sync_gift_inventory_message_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.message_id is not null then
    update public.messages
    set gift_id = new.gift_id
    where id = new.message_id;
  end if;

  return new;
end;
$$;

drop trigger if exists sync_gift_inventory_message_id on public.user_gift_inventory;
create trigger sync_gift_inventory_message_id
  after insert
  on public.user_gift_inventory
  for each row
  execute function public.sync_gift_inventory_message_id();
