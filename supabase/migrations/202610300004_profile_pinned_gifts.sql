alter table public.user_gift_inventory
  add column if not exists is_pinned boolean not null default false,
  add column if not exists pinned_at timestamptz;

create index if not exists user_gift_inventory_pinned_profile_idx
  on public.user_gift_inventory(recipient_id, pinned_at desc)
  where is_pinned;

create or replace function public.set_user_gift_pinned(
  p_inventory_id uuid,
  p_is_pinned boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  gift public.user_gift_inventory%rowtype;
  new_pinned_at timestamptz;
  pinned_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if p_inventory_id is null or p_is_pinned is null then
    raise exception 'Gift and pin state are required'
      using errcode = '22023';
  end if;

  perform 1
  from auth.users
  where id = auth.uid()
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  select *
  into gift
  from public.user_gift_inventory
  where id = p_inventory_id
    and recipient_id = auth.uid()
  for update;

  if not found then
    raise exception 'Gift not found or not owned by current user'
      using errcode = '42501';
  end if;

  if p_is_pinned and not gift.is_pinned then
    select count(*)::integer
    into pinned_count
    from public.user_gift_inventory
    where recipient_id = auth.uid()
      and is_pinned;

    if pinned_count >= 6 then
      raise exception 'A maximum of 6 gifts can be pinned'
        using errcode = '22023';
    end if;
  end if;

  new_pinned_at := case
    when p_is_pinned then coalesce(gift.pinned_at, now())
    else null
  end;

  update public.user_gift_inventory
  set is_pinned = p_is_pinned,
      pinned_at = new_pinned_at
  where id = gift.id;

  select count(*)::integer
  into pinned_count
  from public.user_gift_inventory
  where recipient_id = auth.uid()
    and is_pinned;

  return jsonb_build_object(
    'inventory_id', gift.id,
    'is_pinned', p_is_pinned,
    'pinned_at', new_pinned_at,
    'pinned_count', pinned_count
  );
end;
$$;

revoke all on function public.set_user_gift_pinned(uuid, boolean)
  from public, anon;
grant execute on function public.set_user_gift_pinned(uuid, boolean)
  to authenticated;

drop function if exists public.get_user_received_gifts(uuid);

create function public.get_user_received_gifts(p_user_id uuid)
returns table (
  id uuid,
  gift_id text,
  gift_name text,
  gift_emoji text,
  sender_name text,
  caption text,
  created_at timestamptz,
  nft_serial bigint,
  nft_variant_id text,
  nft_skin_name text,
  nft_skin_emoji text,
  nft_background_color text,
  nft_pattern text,
  nft_animation_url text,
  nft_upgraded_at timestamptz,
  is_pinned boolean,
  pinned_at timestamptz
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
         inventory.created_at,
         inventory.nft_serial,
         inventory.nft_variant_id,
         variant.skin_name,
         variant.skin_emoji,
         variant.background_color,
         variant.pattern,
         variant.animation_url,
         inventory.nft_upgraded_at,
         inventory.is_pinned,
         inventory.pinned_at
  from public.user_gift_inventory as inventory
  left join public.gift_nft_variants as variant
    on variant.id = inventory.nft_variant_id
  where inventory.recipient_id = p_user_id
  order by inventory.is_pinned desc,
           inventory.pinned_at desc nulls last,
           inventory.created_at desc;
end;
$$;

revoke all on function public.get_user_received_gifts(uuid) from public;
grant execute on function public.get_user_received_gifts(uuid) to authenticated;
