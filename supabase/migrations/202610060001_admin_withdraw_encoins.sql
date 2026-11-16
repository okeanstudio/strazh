create or replace function public.withdraw_encoins_admin(
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
    raise exception 'Only platform admins can withdraw Encoins'
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
  if current_balance < p_amount then
    raise exception 'Insufficient Encoins balance'
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
  where id = p_user_id;

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
    'admin_withdraw',
    -p_amount,
    left(
      'Списание администратором'
        || case
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

revoke all on function public.withdraw_encoins_admin(uuid, integer, text)
  from public;
grant execute on function public.withdraw_encoins_admin(uuid, integer, text)
  to authenticated;
