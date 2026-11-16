create table if not exists public.gift_catalog (
  id text primary key,
  name text not null,
  emoji text not null,
  price_enc integer not null check (price_enc > 0),
  sort_order integer not null default 0,
  is_active boolean not null default true
);

insert into public.gift_catalog (id, name, emoji, price_enc, sort_order)
values
  ('rose', 'Роза', '🌹', 10, 1),
  ('heart', 'Сердце', '💝', 25, 2),
  ('cake', 'Торт', '🎂', 50, 3),
  ('teddy', 'Мишка', '🧸', 100, 4),
  ('diamond', 'Бриллиант', '💎', 250, 5),
  ('crown', 'Корона', '👑', 500, 6)
on conflict (id) do update
set name = excluded.name,
    emoji = excluded.emoji,
    price_enc = excluded.price_enc,
    sort_order = excluded.sort_order;

alter table public.gift_catalog enable row level security;
grant select on public.gift_catalog to authenticated;

drop policy if exists "Authenticated users can view active gifts"
  on public.gift_catalog;
create policy "Authenticated users can view active gifts"
  on public.gift_catalog
  for select
  to authenticated
  using (is_active);

create table if not exists public.user_gift_inventory (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references auth.users(id) on delete set null,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  gift_id text not null references public.gift_catalog(id),
  gift_name text not null,
  gift_emoji text not null,
  sender_name text not null,
  price_enc integer not null,
  caption text not null default '',
  room_id uuid not null references public.rooms(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists user_gift_inventory_recipient_created_idx
  on public.user_gift_inventory(recipient_id, created_at desc);
create index if not exists user_gift_inventory_sender_created_idx
  on public.user_gift_inventory(sender_id, created_at desc);

alter table public.user_gift_inventory enable row level security;
grant select on public.user_gift_inventory to authenticated;

drop policy if exists "Users can view gifts they sent or received"
  on public.user_gift_inventory;
create policy "Users can view gifts they sent or received"
  on public.user_gift_inventory
  for select
  to authenticated
  using (sender_id = auth.uid() or recipient_id = auth.uid());

alter table public.messages
  add column if not exists is_gift boolean not null default false;
alter table public.messages
  add column if not exists gift_name text;
alter table public.messages
  add column if not exists gift_emoji text;
alter table public.messages
  add column if not exists gift_price_enc integer;
alter table public.messages
  add column if not exists gift_caption text;

create or replace function public.send_gift(
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
  sender auth.users%rowtype;
  recipient_id uuid;
  gift public.gift_catalog%rowtype;
  current_balance bigint;
  new_balance bigint;
  inserted_message_id uuid;
  message_time timestamptz := now();
  sender_name text;
  sender_tag text;
  sender_avatar text;
  clean_caption text := left(coalesce(trim(p_caption), ''), 120);
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select *
  into gift
  from public.gift_catalog
  where id = p_gift_id
    and is_active;

  if not found then
    raise exception 'Gift is not available'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.rooms
    where id = p_room_id
      and type = 'direct'
  ) then
    raise exception 'Gifts can only be sent in direct chats'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.room_participants
    where room_id = p_room_id
      and user_id = auth.uid()
  ) then
    raise exception 'You are not a member of this chat'
      using errcode = '42501';
  end if;

  select participant.user_id
  into recipient_id
  from public.room_participants as participant
  where participant.room_id = p_room_id
    and participant.user_id <> auth.uid()
  limit 1;

  if recipient_id is null or (
    select count(*)
    from public.room_participants
    where room_id = p_room_id
  ) <> 2 then
    raise exception 'Direct chat recipient could not be determined'
      using errcode = '22023';
  end if;

  select *
  into sender
  from auth.users
  where id = auth.uid()
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if coalesce(sender.raw_user_meta_data ->> 'encoins', '0') !~ '^[0-9]+$' then
    raise exception 'Invalid Encoins balance'
      using errcode = '22023';
  end if;

  current_balance := coalesce(
    (sender.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );
  if current_balance < gift.price_enc then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;
  new_balance := current_balance - gift.price_enc;

  sender_name := coalesce(
    nullif(sender.raw_user_meta_data ->> 'name', ''),
    nullif(sender.raw_user_meta_data ->> 'full_name', ''),
    'Пользователь'
  );
  sender_tag := coalesce(sender.raw_user_meta_data ->> 'tag', '');
  sender_avatar := sender.raw_user_meta_data ->> 'avatar_url';

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{encoins}',
    to_jsonb(new_balance),
    true
  )
  where id = auth.uid();

  insert into public.messages (
    room_id,
    profile_id,
    sender_name,
    sender_tag,
    sender_avatar,
    encrypted_content,
    encrypted_content_type,
    is_gift,
    gift_name,
    gift_emoji,
    gift_price_enc,
    gift_caption,
    created_at
  )
  values (
    p_room_id,
    auth.uid(),
    sender_name,
    sender_tag,
    sender_avatar,
    'Подарок: ' || gift.name,
    'gift',
    true,
    gift.name,
    gift.emoji,
    gift.price_enc,
    clean_caption,
    message_time
  )
  returning id into inserted_message_id;

  insert into public.user_gift_inventory (
    sender_id,
    recipient_id,
    gift_id,
    gift_name,
    gift_emoji,
    sender_name,
    price_enc,
    caption,
    room_id,
    message_id,
    created_at
  )
  values (
    auth.uid(),
    recipient_id,
    gift.id,
    gift.name,
    gift.emoji,
    sender_name,
    gift.price_enc,
    clean_caption,
    p_room_id,
    inserted_message_id,
    message_time
  );

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
    -gift.price_enc,
    'Подарок ' || gift.name || ' для ' || recipient_id::text,
    current_balance::integer,
    new_balance::integer,
    auth.uid()
  );

  return jsonb_build_object(
    'message_id', inserted_message_id,
    'balance', new_balance,
    'recipient_id', recipient_id
  );
end;
$$;

revoke all on function public.send_gift(uuid, text, text) from public;
grant execute on function public.send_gift(uuid, text, text) to authenticated;
