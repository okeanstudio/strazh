alter table public.messages
  add column if not exists gift_nft_serial bigint,
  add column if not exists gift_nft_skin_name text,
  add column if not exists gift_nft_skin_emoji text,
  add column if not exists gift_nft_background_color text,
  add column if not exists gift_nft_pattern text,
  add column if not exists gift_nft_animation_url text;

create or replace function public.sync_gift_nft_message_preview()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  variant public.gift_nft_variants%rowtype;
begin
  if new.nft_variant_id is not null then
    select *
    into variant
    from public.gift_nft_variants
    where id = new.nft_variant_id;
  end if;

  update public.messages
  set gift_nft_serial = new.nft_serial,
      gift_nft_skin_name = variant.skin_name,
      gift_nft_skin_emoji = variant.skin_emoji,
      gift_nft_background_color = variant.background_color,
      gift_nft_pattern = variant.pattern,
      gift_nft_animation_url = variant.animation_url
  where id = new.message_id;

  return new;
end;
$$;

drop trigger if exists sync_gift_nft_message_preview
  on public.user_gift_inventory;
create trigger sync_gift_nft_message_preview
  after insert or update of nft_serial, nft_variant_id
  on public.user_gift_inventory
  for each row
  execute function public.sync_gift_nft_message_preview();

update public.messages as message
set gift_nft_serial = inventory.nft_serial,
    gift_nft_skin_name = variant.skin_name,
    gift_nft_skin_emoji = variant.skin_emoji,
    gift_nft_background_color = variant.background_color,
    gift_nft_pattern = variant.pattern,
    gift_nft_animation_url = variant.animation_url
from public.user_gift_inventory as inventory
left join public.gift_nft_variants as variant
  on variant.id = inventory.nft_variant_id
where inventory.message_id = message.id
  and inventory.nft_serial is not null;

create or replace function public.get_gift_details(p_message_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  gift public.user_gift_inventory%rowtype;
  variant public.gift_nft_variants%rowtype;
  sender auth.users%rowtype;
  recipient auth.users%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select *
  into gift
  from public.user_gift_inventory
  where message_id = p_message_id;

  if not found or (
    gift.nft_serial is null
    and gift.sender_id is distinct from auth.uid()
    and gift.recipient_id is distinct from auth.uid()
  ) then
    raise exception 'Gift not found or not visible to current user'
      using errcode = '42501';
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

revoke all on function public.get_gift_details(uuid) from public, anon;
grant execute on function public.get_gift_details(uuid) to authenticated;

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
    and regexp_replace(inventory.gift_name, '[^A-Za-z0-9]', '', 'g')
        ilike parsed_slug[1]
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
