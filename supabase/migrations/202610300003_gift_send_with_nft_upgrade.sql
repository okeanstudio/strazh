create or replace function public.send_gift_with_upgrade(
  p_room_id uuid,
  p_gift_id text,
  p_caption text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  sent_gift jsonb;
  upgraded_gift jsonb;
  inventory_id uuid;
begin
  sent_gift := public.send_gift(p_room_id, p_gift_id, p_caption);

  select inventory.id
  into inventory_id
  from public.user_gift_inventory as inventory
  where inventory.message_id = (sent_gift ->> 'message_id')::uuid;

  if inventory_id is null then
    raise exception 'Gift inventory entry could not be found'
      using errcode = 'P0002';
  end if;

  upgraded_gift := public.upgrade_gift_to_nft(inventory_id);

  return sent_gift || upgraded_gift;
end;
$$;

revoke all on function public.send_gift_with_upgrade(uuid, text, text)
  from public, anon;
grant execute on function public.send_gift_with_upgrade(uuid, text, text)
  to authenticated;
