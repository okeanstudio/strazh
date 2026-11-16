create table if not exists public.gift_nft_variants (
  id text primary key,
  gift_id text not null references public.gift_catalog(id) on delete cascade,
  skin_name text not null,
  skin_emoji text not null,
  background_color text not null
    check (background_color ~ '^#[0-9A-Fa-f]{6}$'),
  pattern text not null
    check (pattern in ('stars', 'diamonds', 'rings', 'dots')),
  animation_url text,
  weight integer not null default 1 check (weight > 0),
  is_active boolean not null default true
);

alter table public.gift_nft_variants enable row level security;
revoke all on public.gift_nft_variants from public, anon, authenticated;

insert into public.gift_nft_variants (
  id,
  gift_id,
  skin_name,
  skin_emoji,
  background_color,
  pattern,
  weight
)
select gift.id || '_' || variant.id,
       gift.id,
       variant.skin_name,
       variant.skin_emoji,
       variant.background_color,
       variant.pattern,
       1
from public.gift_catalog as gift
cross join (
  values
    ('aurora', 'Северное сияние', '🌌', '#315C91', 'stars'),
    ('gold', 'Золотой узор', '✨', '#8A5A24', 'diamonds'),
    ('nebula', 'Туманность', '🔮', '#653A87', 'rings'),
    ('mint', 'Мятный блеск', '❄️', '#28756B', 'dots')
) as variant(id, skin_name, skin_emoji, background_color, pattern)
on conflict (id) do nothing;

alter table public.user_gift_inventory
  add column if not exists nft_serial bigint,
  add column if not exists nft_variant_id text
    references public.gift_nft_variants(id) on delete set null,
  add column if not exists nft_upgraded_at timestamptz;

create unique index if not exists user_gift_inventory_nft_serial_idx
  on public.user_gift_inventory(gift_id, nft_serial)
  where nft_serial is not null;

create table if not exists public.gift_nft_counters (
  gift_id text primary key references public.gift_catalog(id) on delete cascade,
  last_serial bigint not null check (last_serial > 0)
);

alter table public.gift_nft_counters enable row level security;
revoke all on public.gift_nft_counters from public, anon, authenticated;

create or replace function public.upgrade_gift_to_nft(p_inventory_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  upgrade_cost constant integer := 25;
  inventory public.user_gift_inventory%rowtype;
  gift_variant public.gift_nft_variants%rowtype;
  target_user auth.users%rowtype;
  balance_before bigint;
  balance_after bigint;
  total_weight bigint;
  variant_pick bigint;
  assigned_serial bigint;
  upgraded_at timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select *
  into inventory
  from public.user_gift_inventory
  where id = p_inventory_id
  for update;

  if not found or inventory.recipient_id <> auth.uid() then
    raise exception 'Gift not found or not owned by current user'
      using errcode = '42501';
  end if;

  if inventory.nft_serial is not null then
    select *
    into gift_variant
    from public.gift_nft_variants
    where id = inventory.nft_variant_id;

    return jsonb_build_object(
      'inventory_id', inventory.id,
      'gift_id', inventory.gift_id,
      'nft_serial', inventory.nft_serial,
      'nft_variant_id', inventory.nft_variant_id,
      'nft_skin_name', gift_variant.skin_name,
      'nft_skin_emoji', gift_variant.skin_emoji,
      'nft_background_color', gift_variant.background_color,
      'nft_pattern', gift_variant.pattern,
      'nft_animation_url', gift_variant.animation_url,
      'nft_upgraded_at', inventory.nft_upgraded_at,
      'cost_enc', 0,
      'already_upgraded', true
    );
  end if;

  select *
  into target_user
  from auth.users
  where id = auth.uid()
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if coalesce(target_user.raw_user_meta_data ->> 'encoins', '0') !~ '^[0-9]+$' then
    raise exception 'Invalid Encoins balance'
      using errcode = '22023';
  end if;

  balance_before := coalesce(
    (target_user.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );
  if balance_before < upgrade_cost then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;

  select sum(weight)
  into total_weight
  from public.gift_nft_variants
  where gift_id = inventory.gift_id
    and is_active;

  if coalesce(total_weight, 0) = 0 then
    raise exception 'No active NFT variants for this gift'
      using errcode = '22023';
  end if;

  variant_pick := floor(random() * total_weight);

  select weighted_variant.id,
         weighted_variant.gift_id,
         weighted_variant.skin_name,
         weighted_variant.skin_emoji,
         weighted_variant.background_color,
         weighted_variant.pattern,
         weighted_variant.animation_url,
         weighted_variant.weight,
         weighted_variant.is_active
  into gift_variant
  from (
    select variant.*,
           sum(variant.weight) over (order by variant.id) as cumulative_weight
    from public.gift_nft_variants as variant
    where variant.gift_id = inventory.gift_id
      and variant.is_active
  ) as weighted_variant
  where weighted_variant.cumulative_weight > variant_pick
  order by weighted_variant.cumulative_weight
  limit 1;

  insert into public.gift_nft_counters (gift_id, last_serial)
  values (inventory.gift_id, 1)
  on conflict (gift_id) do update
    set last_serial = public.gift_nft_counters.last_serial + 1
  returning last_serial into assigned_serial;

  balance_after := balance_before - upgrade_cost;

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{encoins}',
    to_jsonb(balance_after),
    true
  )
  where id = auth.uid();

  update public.user_gift_inventory
  set nft_serial = assigned_serial,
      nft_variant_id = gift_variant.id,
      nft_upgraded_at = upgraded_at
  where id = inventory.id;

  insert into public.encoins_transactions (
    user_id,
    type,
    amount,
    description,
    balance_before,
    balance_after,
    performed_by
  )
  values (
    auth.uid(),
    'spend',
    -upgrade_cost,
    'Улучшение подарка ' || inventory.gift_name || ' до NFT',
    balance_before::integer,
    balance_after::integer,
    auth.uid()
  );

  return jsonb_build_object(
    'inventory_id', inventory.id,
    'gift_id', inventory.gift_id,
    'nft_serial', assigned_serial,
    'nft_variant_id', gift_variant.id,
    'nft_skin_name', gift_variant.skin_name,
    'nft_skin_emoji', gift_variant.skin_emoji,
    'nft_background_color', gift_variant.background_color,
    'nft_pattern', gift_variant.pattern,
    'nft_animation_url', gift_variant.animation_url,
    'nft_upgraded_at', upgraded_at,
    'cost_enc', upgrade_cost,
    'balance', balance_after,
    'already_upgraded', false
  );
end;
$$;

revoke all on function public.upgrade_gift_to_nft(uuid) from public;
grant execute on function public.upgrade_gift_to_nft(uuid) to authenticated;

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
  nft_upgraded_at timestamptz
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
         inventory.nft_upgraded_at
  from public.user_gift_inventory as inventory
  left join public.gift_nft_variants as variant
    on variant.id = inventory.nft_variant_id
  where inventory.recipient_id = p_user_id
  order by inventory.created_at desc;
end;
$$;

revoke all on function public.get_user_received_gifts(uuid) from public;
grant execute on function public.get_user_received_gifts(uuid) to authenticated;
