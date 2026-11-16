alter table public.encoins_transactions
  add column if not exists performed_by uuid
    references auth.users(id) on delete set null;

create index if not exists encoins_transactions_created_idx
  on public.encoins_transactions(created_at desc);

create or replace function public.set_encoins_transaction_actor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.performed_by is null then
    new.performed_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists encoins_transactions_set_actor
  on public.encoins_transactions;
create trigger encoins_transactions_set_actor
  before insert on public.encoins_transactions
  for each row
  execute function public.set_encoins_transaction_actor();

create or replace function public.get_encoins_admin_users()
returns table (
  id uuid,
  name text,
  tag text,
  email text,
  avatar_url text,
  encoins integer
)
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'Only platform admins can view Encoins balances'
      using errcode = '42501';
  end if;

  return query
  select
    user_record.id,
    coalesce(
      nullif(user_record.raw_user_meta_data ->> 'name', ''),
      nullif(user_record.raw_user_meta_data ->> 'full_name', ''),
      nullif(user_record.email, ''),
      'Без имени'
    )::text,
    coalesce(user_record.raw_user_meta_data ->> 'tag', '')::text,
    coalesce(user_record.email, '')::text,
    (user_record.raw_user_meta_data ->> 'avatar_url')::text,
    case
      when coalesce(user_record.raw_user_meta_data ->> 'encoins', '') ~ '^[0-9]+$'
        then least(
          (user_record.raw_user_meta_data ->> 'encoins')::numeric,
          2147483647
        )::integer
      else 0
    end
  from auth.users as user_record
  order by lower(
    coalesce(
      user_record.raw_user_meta_data ->> 'name',
      user_record.email,
      ''
    )
  );
end;
$$;

create or replace function public.get_encoins_admin_transactions()
returns table (
  id uuid,
  user_id uuid,
  user_name text,
  user_tag text,
  performed_by uuid,
  actor_name text,
  actor_tag text,
  type text,
  amount integer,
  description text,
  balance_before integer,
  balance_after integer,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'Only platform admins can view Encoins transactions'
      using errcode = '42501';
  end if;

  return query
  select
    transaction.id,
    transaction.user_id,
    coalesce(
      nullif(recipient.raw_user_meta_data ->> 'name', ''),
      nullif(recipient.raw_user_meta_data ->> 'full_name', ''),
      nullif(recipient.email, ''),
      'Без имени'
    )::text,
    coalesce(recipient.raw_user_meta_data ->> 'tag', '')::text,
    transaction.performed_by,
    coalesce(
      nullif(actor.raw_user_meta_data ->> 'name', ''),
      nullif(actor.raw_user_meta_data ->> 'full_name', ''),
      nullif(actor.email, ''),
      case
        when transaction.performed_by is not null then 'Без имени'
        when transaction.description like 'Выдача от %' then
          nullif(
            split_part(
              split_part(transaction.description, 'Выдача от ', 2),
              ':',
              1
            ),
            ''
          )
        else 'Не записан'
      end
    )::text,
    coalesce(actor.raw_user_meta_data ->> 'tag', '')::text,
    transaction.type::text,
    transaction.amount,
    transaction.description::text,
    transaction.balance_before,
    transaction.balance_after,
    transaction.created_at
  from public.encoins_transactions as transaction
  left join auth.users as recipient on recipient.id = transaction.user_id
  left join auth.users as actor on actor.id = transaction.performed_by
  order by transaction.created_at desc, transaction.id desc;
end;
$$;

revoke all on function public.get_encoins_admin_users() from public;
revoke all on function public.get_encoins_admin_transactions() from public;
grant execute on function public.get_encoins_admin_users() to authenticated;
grant execute on function public.get_encoins_admin_transactions() to authenticated;
