create table if not exists public.encoins_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  amount integer not null,
  description text not null default '',
  balance_before integer not null,
  balance_after integer not null,
  created_at timestamptz not null default now()
);

create index if not exists encoins_transactions_user_created_idx
  on public.encoins_transactions(user_id, created_at desc);

alter table public.encoins_transactions enable row level security;

drop policy if exists "Users can read own encoins transactions"
  on public.encoins_transactions;
create policy "Users can read own encoins transactions"
  on public.encoins_transactions
  for select
  to authenticated
  using (user_id = auth.uid());

create table if not exists public.subscriptions_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null,
  plan_title text not null,
  price_rub integer not null,
  price_enc integer not null,
  payment_method text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists subscriptions_history_user_created_idx
  on public.subscriptions_history(user_id, created_at desc);

alter table public.subscriptions_history enable row level security;

drop policy if exists "Users can read own subscription history"
  on public.subscriptions_history;
create policy "Users can read own subscription history"
  on public.subscriptions_history
  for select
  to authenticated
  using (user_id = auth.uid());

create or replace function public.grant_encoins(
  p_user_id uuid,
  p_amount integer,
  p_description text default ''
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user auth.users%rowtype;
  current_balance bigint;
  new_balance bigint;
  admin_name text;
begin
  if auth.uid() is null
    or (
      coalesce(auth.jwt() #>> '{user_metadata,role}', '') not in (
        'moderator', 'admin', 'owner'
      )
      and coalesce(auth.jwt() #>> '{app_metadata,role}', '') not in (
        'moderator', 'admin', 'owner'
      )
    ) then
    raise exception 'Only platform admins can grant Encoins'
      using errcode = '42501';
  end if;

  if p_user_id is null or p_amount is null or p_amount < 1 or p_amount > 1000000000 then
    raise exception 'Amount must be between 1 and 1000000000'
      using errcode = '22023';
  end if;

  select *
  into target_user
  from auth.users
  where id = p_user_id
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if coalesce(target_user.raw_user_meta_data ->> 'encoins', '0') !~ '^[0-9]+$' then
    raise exception 'User has an invalid Encoins balance'
      using errcode = '22023';
  end if;

  current_balance := coalesce(
    (target_user.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );
  new_balance := current_balance + p_amount;

  if new_balance > 2147483647 then
    raise exception 'Encoins balance limit exceeded'
      using errcode = '22003';
  end if;

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{encoins}',
    to_jsonb(new_balance),
    true
  )
  where id = p_user_id;

  admin_name := coalesce(
    auth.jwt() #>> '{user_metadata,name}',
    auth.jwt() #>> '{user_metadata,full_name}',
    'Администратор'
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
    p_user_id,
    'bonus',
    p_amount,
    left(
      'Выдача от ' || admin_name || case
        when coalesce(trim(p_description), '') = '' then ''
        else ': ' || trim(p_description)
      end,
      250
    ),
    current_balance::integer,
    new_balance::integer
  );

  return new_balance::integer;
end;
$$;

create or replace function public.spend_encoins(
  p_amount integer,
  p_description text default 'Списание'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user auth.users%rowtype;
  current_balance bigint;
  new_balance bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if p_amount is null or p_amount < 1 or p_amount > 1000000000 then
    raise exception 'Amount must be between 1 and 1000000000'
      using errcode = '22023';
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

  current_balance := coalesce(
    (target_user.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );

  if current_balance < p_amount then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;

  new_balance := current_balance - p_amount;

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(raw_user_meta_data, '{}'::jsonb),
    '{encoins}',
    to_jsonb(new_balance),
    true
  )
  where id = auth.uid();

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
    -p_amount,
    left(coalesce(nullif(trim(p_description), ''), 'Списание'), 250),
    current_balance::integer,
    new_balance::integer
  );

  return new_balance::integer;
end;
$$;

create or replace function public.purchase_subscription_with_encoins(
  p_plan_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user auth.users%rowtype;
  current_balance bigint;
  new_balance bigint;
  plan_title text;
  price_rub integer;
  price_enc integer;
  duration_days integer;
  existing_expiry timestamptz;
  new_expiry timestamptz;
  current_expiry_text text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
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

  current_balance := coalesce(
    (target_user.raw_user_meta_data ->> 'encoins')::bigint,
    0
  );

  if current_balance < price_enc then
    raise exception 'Insufficient Encoins'
      using errcode = '22023';
  end if;

  current_expiry_text :=
    target_user.raw_user_meta_data ->> 'subscription_expires_at';

  if lower(coalesce(current_expiry_text, '')) = 'forever' then
    raise exception 'Permanent subscription is already active'
      using errcode = '22023';
  end if;

  if coalesce(target_user.raw_user_meta_data ->> 'subscription_type', '') = 'premium'
    and current_expiry_text is not null then
    begin
      existing_expiry := current_expiry_text::timestamptz;
    exception when others then
      existing_expiry := null;
    end;
  end if;

  new_expiry := greatest(coalesce(existing_expiry, now()), now())
    + make_interval(days => duration_days);
  new_balance := current_balance - price_enc;

  update auth.users
  set raw_user_meta_data = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          coalesce(raw_user_meta_data, '{}'::jsonb),
          '{encoins}',
          to_jsonb(new_balance),
          true
        ),
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
  where id = auth.uid();

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
    'Покупка подписки: ' || plan_title,
    current_balance::integer,
    new_balance::integer
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
    auth.uid(),
    p_plan_id,
    plan_title,
    price_rub,
    price_enc,
    'enc',
    new_expiry
  );

  return jsonb_build_object(
    'balance', new_balance,
    'expires_at', new_expiry
  );
end;
$$;

revoke all on function public.grant_encoins(uuid, integer, text) from public;
revoke all on function public.spend_encoins(integer, text) from public;
revoke all on function public.purchase_subscription_with_encoins(text) from public;

grant execute on function public.grant_encoins(uuid, integer, text) to authenticated;
grant execute on function public.spend_encoins(integer, text) to authenticated;
grant execute on function public.purchase_subscription_with_encoins(text) to authenticated;
