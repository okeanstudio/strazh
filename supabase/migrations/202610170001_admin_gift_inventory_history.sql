create table if not exists public.gift_inventory_history (
  id bigint generated always as identity primary key,
  inventory_id uuid not null,
  action text not null check (action in ('issued', 'revoked', 'removed')),
  recipient_id uuid,
  recipient_name text not null,
  sender_id uuid,
  sender_name text not null,
  gift_id text not null,
  gift_name text not null,
  gift_emoji text not null,
  price_enc integer not null,
  caption text not null default '',
  room_id uuid,
  message_id uuid,
  source text not null check (source in ('admin', 'chat')),
  actor_id uuid,
  actor_name text not null,
  created_at timestamptz not null
);

create index if not exists gift_inventory_history_created_idx
  on public.gift_inventory_history(created_at desc);
create index if not exists gift_inventory_history_recipient_idx
  on public.gift_inventory_history(recipient_id, created_at desc);

alter table public.gift_inventory_history enable row level security;

insert into public.gift_inventory_history (
  inventory_id,
  action,
  recipient_id,
  recipient_name,
  sender_id,
  sender_name,
  gift_id,
  gift_name,
  gift_emoji,
  price_enc,
  caption,
  room_id,
  message_id,
  source,
  actor_id,
  actor_name,
  created_at
)
select
  inventory.id,
  'issued',
  inventory.recipient_id,
  coalesce(
    nullif(recipient.raw_user_meta_data ->> 'name', ''),
    nullif(recipient.raw_user_meta_data ->> 'full_name', ''),
    'Пользователь'
  ),
  inventory.sender_id,
  inventory.sender_name,
  inventory.gift_id,
  inventory.gift_name,
  inventory.gift_emoji,
  inventory.price_enc,
  inventory.caption,
  inventory.room_id,
  inventory.message_id,
  case when inventory.room_id is null then 'admin' else 'chat' end,
  inventory.sender_id,
  inventory.sender_name,
  inventory.created_at
from public.user_gift_inventory as inventory
left join auth.users as recipient on recipient.id = inventory.recipient_id;

create or replace function public.audit_gift_inventory_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_user auth.users%rowtype;
  actor_user auth.users%rowtype;
  event_action text;
  event_actor_id uuid;
  event_actor_name text;
begin
  if tg_op = 'INSERT' then
    select *
    into recipient_user
    from auth.users
    where id = new.recipient_id;

    event_actor_id := coalesce(auth.uid(), new.sender_id);
    select *
    into actor_user
    from auth.users
    where id = event_actor_id;

    event_actor_name := coalesce(
      nullif(actor_user.raw_user_meta_data ->> 'name', ''),
      nullif(actor_user.raw_user_meta_data ->> 'full_name', ''),
      new.sender_name
    );

    insert into public.gift_inventory_history (
      inventory_id,
      action,
      recipient_id,
      recipient_name,
      sender_id,
      sender_name,
      gift_id,
      gift_name,
      gift_emoji,
      price_enc,
      caption,
      room_id,
      message_id,
      source,
      actor_id,
      actor_name,
      created_at
    )
    values (
      new.id,
      'issued',
      new.recipient_id,
      coalesce(
        nullif(recipient_user.raw_user_meta_data ->> 'name', ''),
        nullif(recipient_user.raw_user_meta_data ->> 'full_name', ''),
        'Пользователь'
      ),
      new.sender_id,
      new.sender_name,
      new.gift_id,
      new.gift_name,
      new.gift_emoji,
      new.price_enc,
      new.caption,
      new.room_id,
      new.message_id,
      case when new.room_id is null then 'admin' else 'chat' end,
      event_actor_id,
      event_actor_name,
      new.created_at
    );
    return new;
  end if;

  event_actor_id := auth.uid();
  select *
  into recipient_user
  from auth.users
  where id = old.recipient_id;

  select *
  into actor_user
  from auth.users
  where id = event_actor_id;

  event_actor_name := coalesce(
    nullif(actor_user.raw_user_meta_data ->> 'name', ''),
    nullif(actor_user.raw_user_meta_data ->> 'full_name', ''),
    'Система'
  );
  event_action := case
    when current_setting('app.gift_inventory_action', true) = 'revoked'
      then 'revoked'
    else 'removed'
  end;

  insert into public.gift_inventory_history (
    inventory_id,
    action,
    recipient_id,
    recipient_name,
    sender_id,
    sender_name,
    gift_id,
    gift_name,
    gift_emoji,
    price_enc,
    caption,
    room_id,
    message_id,
    source,
    actor_id,
    actor_name,
    created_at
  )
  values (
    old.id,
    event_action,
    old.recipient_id,
    coalesce(
      nullif(recipient_user.raw_user_meta_data ->> 'name', ''),
      nullif(recipient_user.raw_user_meta_data ->> 'full_name', ''),
      'Пользователь'
    ),
    old.sender_id,
    old.sender_name,
    old.gift_id,
    old.gift_name,
    old.gift_emoji,
    old.price_enc,
    old.caption,
    old.room_id,
    old.message_id,
    case when old.room_id is null then 'admin' else 'chat' end,
    event_actor_id,
    event_actor_name,
    now()
  );
  return old;
end;
$$;

revoke all on function public.audit_gift_inventory_change() from public;

drop trigger if exists audit_gift_inventory_change
  on public.user_gift_inventory;
create trigger audit_gift_inventory_change
after insert or delete on public.user_gift_inventory
for each row execute function public.audit_gift_inventory_change();

create or replace function public.get_admin_user_gifts(p_user_id uuid)
returns table (
  id uuid,
  gift_name text,
  gift_emoji text,
  sender_name text,
  price_enc integer,
  caption text,
  created_at timestamptz
)
language plpgsql
stable
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
    raise exception 'Only platform admins can view gift inventory'
      using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'Recipient is required'
      using errcode = '22023';
  end if;

  return query
  select inventory.id,
         inventory.gift_name,
         inventory.gift_emoji,
         inventory.sender_name,
         inventory.price_enc,
         inventory.caption,
         inventory.created_at
  from public.user_gift_inventory as inventory
  where inventory.recipient_id = p_user_id
  order by inventory.created_at desc;
end;
$$;

revoke all on function public.get_admin_user_gifts(uuid) from public;
grant execute on function public.get_admin_user_gifts(uuid) to authenticated;

create or replace function public.revoke_gift_admin(p_inventory_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
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
    raise exception 'Only platform admins can revoke gifts'
      using errcode = '42501';
  end if;

  if p_inventory_id is null then
    raise exception 'Gift is required'
      using errcode = '22023';
  end if;

  perform set_config('app.gift_inventory_action', 'revoked', true);
  delete from public.user_gift_inventory
  where id = p_inventory_id;
  get diagnostics deleted_count = row_count;

  if deleted_count = 0 then
    raise exception 'Gift is not in the user inventory'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.revoke_gift_admin(uuid) from public;
grant execute on function public.revoke_gift_admin(uuid) to authenticated;

create or replace function public.get_admin_gift_history(p_limit integer default 200)
returns table (
  id bigint,
  action text,
  gift_name text,
  gift_emoji text,
  price_enc integer,
  caption text,
  recipient_name text,
  sender_name text,
  actor_name text,
  source text,
  created_at timestamptz
)
language plpgsql
stable
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
    raise exception 'Only platform admins can view gift history'
      using errcode = '42501';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'History limit must be between 1 and 500'
      using errcode = '22023';
  end if;

  return query
  select history.id,
         history.action,
         history.gift_name,
         history.gift_emoji,
         history.price_enc,
         history.caption,
         history.recipient_name,
         history.sender_name,
         history.actor_name,
         history.source,
         history.created_at
  from public.gift_inventory_history as history
  order by history.created_at desc, history.id desc
  limit p_limit;
end;
$$;

revoke all on function public.get_admin_gift_history(integer) from public;
grant execute on function public.get_admin_gift_history(integer) to authenticated;
