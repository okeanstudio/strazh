create or replace function public.get_gift_details_by_slug(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  parsed_slug text[];
  gift_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  parsed_slug := regexp_match(
    coalesce(p_slug, ''),
    '^([A-Za-z0-9]+)-([0-9]+)$'
  );
  if parsed_slug is null then
    raise exception 'Invalid gift URL'
      using errcode = '22023';
  end if;

  select inventory.message_id
  into gift_message_id
  from public.user_gift_inventory as inventory
  where inventory.nft_serial = parsed_slug[2]::bigint
    and (
      regexp_replace(inventory.gift_name, '[^A-Za-z0-9]', '', 'g')
        ilike parsed_slug[1]
      or regexp_replace(inventory.gift_id, '[^A-Za-z0-9]', '', 'g')
        ilike parsed_slug[1]
    )
  order by inventory.nft_upgraded_at desc nulls last
  limit 1;

  if gift_message_id is null then
    raise exception 'Gift not found or not visible to current user'
      using errcode = 'P0002';
  end if;

  return public.get_gift_details(gift_message_id);
end;
$$;

revoke all on function public.get_gift_details_by_slug(text)
  from public, anon;
grant execute on function public.get_gift_details_by_slug(text)
  to authenticated;
