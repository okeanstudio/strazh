create or replace function public.gift_nft_slugify(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  normalized text := lower(coalesce(p_value, ''));
begin
  normalized := replace(normalized, 'ё', 'yo');
  normalized := replace(normalized, 'ж', 'zh');
  normalized := replace(normalized, 'х', 'kh');
  normalized := replace(normalized, 'ц', 'ts');
  normalized := replace(normalized, 'ч', 'ch');
  normalized := replace(normalized, 'ш', 'sh');
  normalized := replace(normalized, 'щ', 'shch');
  normalized := replace(normalized, 'ъ', '');
  normalized := replace(normalized, 'ь', '');
  normalized := replace(normalized, 'ю', 'yu');
  normalized := replace(normalized, 'я', 'ya');
  normalized := translate(
    normalized,
    'абвгдезийклмнопрстуфыэ',
    'abvgdezijklmnoprstufye'
  );
  return regexp_replace(normalized, '[^a-z0-9]', '', 'g');
end;
$$;

revoke all on function public.gift_nft_slugify(text)
  from public, anon, authenticated;

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
  left join public.gift_catalog as catalog
    on catalog.id = inventory.gift_id
  where inventory.nft_serial = parsed_slug[2]::bigint
    and lower(parsed_slug[1]) in (
      public.gift_nft_slugify(inventory.gift_name),
      public.gift_nft_slugify(inventory.gift_id),
      public.gift_nft_slugify(catalog.name),
      public.gift_nft_slugify(catalog.id)
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
