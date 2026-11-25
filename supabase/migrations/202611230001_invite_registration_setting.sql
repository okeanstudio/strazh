create table if not exists public.registration_settings (
  setting_key text primary key,
  boolean_value boolean not null,
  updated_at timestamptz not null default now()
);

insert into public.registration_settings (setting_key, boolean_value)
values ('invite_code_required', true)
on conflict (setting_key) do nothing;

alter table public.registration_settings enable row level security;
revoke all on table public.registration_settings from anon, authenticated;

create or replace function public.get_invite_code_requirement()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select setting.boolean_value
      from public.registration_settings as setting
      where setting.setting_key = 'invite_code_required'
    ),
    true
  );
$$;

revoke all on function public.get_invite_code_requirement() from public;
grant execute on function public.get_invite_code_requirement()
  to anon, authenticated;

create or replace function public.set_invite_code_requirement(p_required boolean)
returns void
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
    )
  then
    raise exception 'Only platform admins can change registration settings'
      using errcode = '42501';
  end if;

  update public.registration_settings
  set boolean_value = p_required, updated_at = now()
  where setting_key = 'invite_code_required';

  if not found then
    raise exception 'Invite registration setting is missing';
  end if;
end;
$$;

revoke all on function public.set_invite_code_requirement(boolean) from public;
grant execute on function public.set_invite_code_requirement(boolean)
  to authenticated;

create or replace function public.activate_without_invite()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_metadata jsonb;
  invite_required boolean;
begin
  if current_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  select setting.boolean_value
  into invite_required
  from public.registration_settings as setting
  where setting.setting_key = 'invite_code_required';
  invite_required := coalesce(invite_required, true);

  if invite_required then
    return jsonb_build_object('ok', false, 'error', 'invite_required');
  end if;

  select raw_user_meta_data
  into current_metadata
  from auth.users
  where id = current_user_id
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  if current_metadata -> 'needs_invite' is distinct from 'true'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'already_activated');
  end if;

  update auth.users
  set raw_user_meta_data =
    coalesce(current_metadata, '{}'::jsonb)
      - 'needs_invite'
      - 'invited_by_code'
    || jsonb_build_object('needs_invite', false)
  where id = current_user_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.activate_without_invite() from public;
grant execute on function public.activate_without_invite() to authenticated;

create or replace function public.consume_invite_code_on_user_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  submitted_code text;
  inviter_id uuid;
  inviter_metadata jsonb;
  candidate_code text;
  own_code text;
  invite_required boolean;
begin
  perform pg_catalog.pg_advisory_xact_lock(8675309::bigint);

  select setting.boolean_value
  into invite_required
  from public.registration_settings as setting
  where setting.setting_key = 'invite_code_required';
  invite_required := coalesce(invite_required, true);

  submitted_code := upper(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'invited_by_code', '')), '')
  );

  if submitted_code is null
    and invite_required
    and new.raw_user_meta_data -> 'needs_invite' is distinct from 'true'::jsonb
  then
    raise exception 'Invite code is required'
      using errcode = '22023';
  end if;

  if submitted_code is not null then
    select id, raw_user_meta_data
    into inviter_id, inviter_metadata
    from auth.users
    where upper(trim(coalesce(raw_user_meta_data ->> 'invite_code', ''))) =
      submitted_code
    for update;

    if inviter_id is null then
      raise exception 'Invalid or already used invite code'
        using errcode = '22023';
    end if;
  end if;

  own_code := upper(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'invite_code', '')), '')
  );

  if submitted_code is not null then
    loop
      candidate_code :=
        pg_catalog.chr(65 + floor(random() * 26)::integer)
        || pg_catalog.chr(65 + floor(random() * 26)::integer)
        || pg_catalog.chr(65 + floor(random() * 26)::integer)
        || lpad(floor(random() * 100000)::integer::text, 5, '0');

      exit when candidate_code <> submitted_code
        and candidate_code is distinct from own_code
        and not exists (
          select 1
          from auth.users
          where upper(trim(coalesce(raw_user_meta_data ->> 'invite_code', ''))) =
            candidate_code
        );
    end loop;

    update auth.users
    set raw_user_meta_data = jsonb_set(
      coalesce(inviter_metadata, '{}'::jsonb),
      '{invite_code}',
      to_jsonb(candidate_code),
      true
    )
    where id = inviter_id;

    new.raw_user_meta_data :=
      coalesce(new.raw_user_meta_data, '{}'::jsonb)
      - 'needs_invite'
      - 'invited_by_code'
      || jsonb_build_object('invited_by_user_id', inviter_id::text);
  else
    new.raw_user_meta_data :=
      coalesce(new.raw_user_meta_data, '{}'::jsonb)
      - 'invited_by_code'
      - 'invited_by_user_id';
    if not invite_required then
      new.raw_user_meta_data := new.raw_user_meta_data - 'needs_invite';
    end if;
  end if;

  if own_code is null
    or own_code = submitted_code
    or exists (
      select 1
      from auth.users
      where upper(trim(coalesce(raw_user_meta_data ->> 'invite_code', ''))) =
        own_code
    )
  then
    loop
      own_code :=
        pg_catalog.chr(65 + floor(random() * 26)::integer)
        || pg_catalog.chr(65 + floor(random() * 26)::integer)
        || pg_catalog.chr(65 + floor(random() * 26)::integer)
        || lpad(floor(random() * 100000)::integer::text, 5, '0');

      exit when own_code is distinct from candidate_code
        and own_code is distinct from submitted_code
        and not exists (
          select 1
          from auth.users
          where upper(trim(coalesce(raw_user_meta_data ->> 'invite_code', ''))) =
            own_code
        );
    end loop;
  end if;

  new.raw_user_meta_data := jsonb_set(
    coalesce(new.raw_user_meta_data, '{}'::jsonb),
    '{invite_code}',
    to_jsonb(own_code),
    true
  );

  return new;
end;
$$;
