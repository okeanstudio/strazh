create table if not exists public.e2ee_devices (
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  registration_id integer not null check (registration_id > 0),
  identity_key text not null,
  signed_pre_key_id integer not null,
  signed_pre_key text not null,
  signed_pre_key_signature text not null,
  one_time_prekeys jsonb not null default '[]'::jsonb
    check (jsonb_typeof(one_time_prekeys) = 'array'),
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

alter table public.e2ee_devices enable row level security;

drop policy if exists "Authenticated users can view public E2E device keys"
  on public.e2ee_devices;
create policy "Authenticated users can view public E2E device keys"
  on public.e2ee_devices
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.room_participants as current_participant
      join public.room_participants as target_participant
        on target_participant.room_id = current_participant.room_id
      where current_participant.user_id = auth.uid()
        and target_participant.user_id = e2ee_devices.user_id
    )
  );

drop policy if exists "Users can publish their own E2E device keys"
  on public.e2ee_devices;
create policy "Users can publish their own E2E device keys"
  on public.e2ee_devices
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update their own E2E device keys"
  on public.e2ee_devices;
create policy "Users can update their own E2E device keys"
  on public.e2ee_devices
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users can delete their own E2E device keys"
  on public.e2ee_devices;
create policy "Users can delete their own E2E device keys"
  on public.e2ee_devices
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.e2ee_devices to authenticated;

create or replace function public.claim_e2ee_prekey(
  p_room_id uuid,
  p_user_id uuid,
  p_device_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  device public.e2ee_devices%rowtype;
  one_time_prekey jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.room_participants as participant
    where participant.room_id = p_room_id
      and participant.user_id = auth.uid()
  ) or not exists (
    select 1
    from public.room_participants as participant
    where participant.room_id = p_room_id
      and participant.user_id = p_user_id
  ) then
    raise exception 'Both users must be room participants'
      using errcode = '42501';
  end if;

  select *
    into device
    from public.e2ee_devices
    where user_id = p_user_id
      and device_id = p_device_id
    for update;

  if not found then
    raise exception 'E2E device not found' using errcode = 'P0002';
  end if;

  if jsonb_array_length(device.one_time_prekeys) = 0 then
    raise exception 'No one-time prekeys are available'
      using errcode = 'P0002';
  end if;

  one_time_prekey := device.one_time_prekeys -> 0;
  update public.e2ee_devices
    set one_time_prekeys = one_time_prekeys - 0,
        updated_at = now()
    where user_id = p_user_id
      and device_id = p_device_id;

  return jsonb_build_object(
    'user_id', device.user_id,
    'device_id', device.device_id,
    'registration_id', device.registration_id,
    'identity_key', device.identity_key,
    'signed_pre_key_id', device.signed_pre_key_id,
    'signed_pre_key', device.signed_pre_key,
    'signed_pre_key_signature', device.signed_pre_key_signature,
    'one_time_prekey', one_time_prekey
  );
end;
$$;

revoke all on function public.claim_e2ee_prekey(uuid, uuid, text) from public;
grant execute on function public.claim_e2ee_prekey(uuid, uuid, text)
  to authenticated;
