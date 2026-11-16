create or replace function public.get_gift_details_by_slug(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  parsed_slug text[];
  requested_slug text;
  gift public.user_gift_inventory%rowtype;
  variant public.gift_nft_variants%rowtype;
  sender auth.users%rowtype;
  recipient auth.users%rowtype;
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
  requested_slug := lower(parsed_slug[1]);

  select inventory.*
  into gift
  from public.user_gift_inventory as inventory
  left join public.gift_catalog as catalog
    on catalog.id = inventory.gift_id
  where inventory.nft_serial = parsed_slug[2]::bigint
    and (
      public.gift_nft_slugify(inventory.gift_name) = requested_slug
      or public.gift_nft_slugify(inventory.gift_id) = requested_slug
      or public.gift_nft_slugify(catalog.name) = requested_slug
      or public.gift_nft_slugify(catalog.id) = requested_slug
    )
  order by inventory.nft_upgraded_at desc nulls last
  limit 1;

  if not found then
    raise exception 'Gift not found'
      using errcode = 'P0002';
  end if;

  if gift.nft_variant_id is not null then
    select *
    into variant
    from public.gift_nft_variants
    where id = gift.nft_variant_id;
  end if;

  select *
  into sender
  from auth.users
  where id = gift.sender_id;

  select *
  into recipient
  from auth.users
  where id = gift.recipient_id;

  return jsonb_build_object(
    'id', gift.id,
    'message_id', gift.message_id,
    'gift_id', gift.gift_id,
    'gift_name', gift.gift_name,
    'gift_emoji', gift.gift_emoji,
    'sender_id', gift.sender_id,
    'sender_name', gift.sender_name,
    'sender_tag', sender.raw_user_meta_data ->> 'tag',
    'recipient_id', gift.recipient_id,
    'owner_name', coalesce(
      recipient.raw_user_meta_data ->> 'name',
      recipient.raw_user_meta_data ->> 'full_name',
      'Пользователь'
    ),
    'owner_tag', recipient.raw_user_meta_data ->> 'tag',
    'owner_avatar_url', recipient.raw_user_meta_data ->> 'avatar_url',
    'price_enc', gift.price_enc,
    'caption', gift.caption,
    'created_at', gift.created_at,
    'is_pinned', gift.is_pinned,
    'nft_serial', gift.nft_serial,
    'nft_variant_id', gift.nft_variant_id,
    'nft_skin_name', variant.skin_name,
    'nft_skin_emoji', variant.skin_emoji,
    'nft_background_color', variant.background_color,
    'nft_pattern', variant.pattern,
    'nft_animation_url', variant.animation_url,
    'nft_upgraded_at', gift.nft_upgraded_at
  );
end;
$$;

revoke all on function public.get_gift_details_by_slug(text)
  from public, anon;
grant execute on function public.get_gift_details_by_slug(text)
  to authenticated;
