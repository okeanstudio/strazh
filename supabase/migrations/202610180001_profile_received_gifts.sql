create or replace function public.get_user_received_gifts(p_user_id uuid)
returns table (
  id uuid,
  gift_id text,
  gift_name text,
  gift_emoji text,
  sender_name text,
  caption text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'Recipient is required'
      using errcode = '22023';
  end if;

  return query
  select inventory.id,
         inventory.gift_id,
         inventory.gift_name,
         inventory.gift_emoji,
         inventory.sender_name,
         inventory.caption,
         inventory.created_at
  from public.user_gift_inventory as inventory
  where inventory.recipient_id = p_user_id
  order by inventory.created_at desc;
end;
$$;

revoke all on function public.get_user_received_gifts(uuid) from public;
grant execute on function public.get_user_received_gifts(uuid) to authenticated;
