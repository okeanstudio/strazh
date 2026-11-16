create or replace function public.gift_subscription_with_encoins(
  p_room_id uuid,
  p_recipient_id uuid,
  p_plan_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender auth.users%rowtype;
  recipient auth.users%rowtype;
  plan_title text;
  price_rub integer;
  price_enc integer;
  duration_days integer;
  sender_balance bigint;
  recipient_balance bigint;
  recipient_expiry_text text;
  recipient_expiry timestamptz;
  new_expiry timestamptz;
  sender_name text;
  sender_tag text;
  sender_avatar text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if p_recipient_id is null
    or p_recipient_id = auth.uid()
    or p_room_id is null then
    raise exception 'A different recipient in a direct chat is required'
      using errcode = '22023';
  end if;

  select
    case p_plan_id
      when '1m' then '1 месяц'
      when '3m' then '3 месяца'
      when '1y' then '1 год'
      when '2y' then '2 года'
    end,
    case p_plan_id
      when '1m' then 199
      when '3m' then 499
      when '1y' then 1499
      when '2y' then 2499
    end,
    case p_plan_id
      when '1m' then 200
      when '3m' then 500
      when '1y' then 1500
      when '2y' then 2500
    end,
    case p_plan_id
      when '1m' then 30
      when '3m' then 90
      when '1y' then 365
      when '2y' then 730
    end
  into plan_title, price_rub, price_enc, duration_days;

  if plan_title is null then
    raise exception 'Unknown subscription plan'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.rooms
    where id = p_room_id
      and type = 'direct'
  ) or not exists (
    select 1
    from public.room_participants as participant
    where participant.room_id = p_room_id
      and participant.user_id = auth.uid()
  ) or not exists (
    select 1
    from public.room_participants as participant
    where participant.room_id = p_room_id
      and participant.user_id = p_recipient_id
  ) or (
    select count(*)
    from public.room_participants as participant
    where participant.room_id = p_room_id
  ) <> 2 then
    raise exception 'Both users must belong to the same direct chat'
      using errcode = '42501';
  end if;

  perform 1
  from auth.users
  where id in (auth.uid(), p_recipient_id)
  order by id
  for update;

  select *
  into sender
  from auth.users
  where id = auth.uid();

  select *
  into recipient
  from auth.users
  where id = p_recipient_id;

  if sender.id is null or recipient.id is null then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if coalesce(sender.raw_user_meta_data ->> 'encoins', '0') !~ '^[0-9]+$' then
    raise exception 'Invalid Encoins balance'
      using errcode = '22023';
  end if;

  sender_balance := coalesce(
    (sender.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );
  if sender_balance < price_enc then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;

  recipient_expiry_text :=
    recipient.raw_user_meta_data ->> 'subscription_expires_at';
  if lower(coalesce(recipient_expiry_text, '')) = 'forever' then
    raise exception 'Recipient already has a permanent subscription'
      using errcode = '22023';
  end if;

  if coalesce(
    recipient.raw_user_meta_data ->> 'subscription_type',
    ''
  ) = 'premium' and recipient_expiry_text is not null then
    begin
      recipient_expiry := recipient_expiry_text::timestamptz;
    exception when others then
      recipient_expiry := null;
    end;
  end if;

  new_expiry := greatest(coalesce(recipient_expiry, now()), now())
    + make_interval(days => duration_days);
  recipient_balance := sender_balance - price_enc;
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
    to_jsonb(recipient_balance),
    true
  )
  where id = auth.uid();

  update auth.users
  set raw_user_meta_data = jsonb_set(
    jsonb_set(
      jsonb_set(
        coalesce(raw_user_meta_data, '{}'::jsonb),
        '{subscription_type}',
        to_jsonb('premium'::text),
        true
      ),
      '{subscription_plan_id}',
      to_jsonb(p_plan_id),
      true
    ),
    '{subscription_expires_at}',
    to_jsonb(new_expiry),
    true
  )
  where id = p_recipient_id;

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
    'Подарок: Strazh Infinity · ' || plan_title,
    'gift',
    true,
    'Strazh Infinity · ' || plan_title,
    '⚡',
    price_enc,
    'Подписка до ' || to_char(new_expiry, 'DD.MM.YYYY'),
    now()
  );

  insert into public.encoins_transactions (
    user_id,
    type,
    amount,
    description,
    balance_before,
    balance_after
  )
  values (
    auth.uid(),
    'spend',
    -price_enc,
    'Подарок Strazh Infinity: ' || plan_title,
    sender_balance::integer,
    recipient_balance::integer
  );

  insert into public.subscriptions_history (
    user_id,
    plan_id,
    plan_title,
    price_rub,
    price_enc,
    payment_method,
    expires_at
  )
  values (
    p_recipient_id,
    p_plan_id,
    plan_title,
    price_rub,
    price_enc,
    'gift_enc',
    new_expiry
  );

  return jsonb_build_object(
    'balance', recipient_balance,
    'recipient_id', p_recipient_id,
    'expires_at', new_expiry
  );
end;
$$;

revoke all on function public.gift_subscription_with_encoins(uuid, uuid, text)
  from public;
grant execute on function public.gift_subscription_with_encoins(uuid, uuid, text)
  to authenticated;
