alter table public.user_gift_inventory
  alter column room_id drop not null,
  alter column message_id drop not null;

create or replace function public.grant_gift_admin(
  p_user_id uuid,
  p_gift_id text,
  p_caption text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  gift public.gift_catalog%rowtype;
  recipient_exists boolean;
  admin_name text;
  inventory_id uuid;
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
    raise exception 'Only platform admins can grant gifts'
      using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'Recipient is required'
      using errcode = '22023';
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

  select exists (
    select 1 from auth.users where id = p_user_id
  )
  into recipient_exists;

  if not recipient_exists then
    raise exception 'Recipient not found'
      using errcode = 'P0002';
  end if;

  admin_name := coalesce(
    nullif(auth.jwt() #>> '{user_metadata,name}', ''),
    nullif(auth.jwt() #>> '{user_metadata,full_name}', ''),
    'Администрация'
  );

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
    message_id
  )
  values (
    auth.uid(),
    p_user_id,
    gift.id,
    gift.name,
    gift.emoji,
    admin_name,
    gift.price_enc,
    left(coalesce(trim(p_caption), ''), 120),
    null,
    null
  )
  returning id into inventory_id;

  return inventory_id;
end;
$$;

revoke all on function public.grant_gift_admin(uuid, text, text) from public;
grant execute on function public.grant_gift_admin(uuid, text, text)
  to authenticated;
