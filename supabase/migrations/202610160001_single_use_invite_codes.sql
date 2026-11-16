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
begin
  perform pg_catalog.pg_advisory_xact_lock(8675309::bigint);

  submitted_code := upper(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'invited_by_code', '')), '')
  );

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
      - 'invited_by_code'
      || jsonb_build_object('invited_by_user_id', inviter_id::text);
  else
    new.raw_user_meta_data :=
      coalesce(new.raw_user_meta_data, '{}'::jsonb)
      - 'invited_by_code'
      - 'invited_by_user_id';
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

drop trigger if exists consume_invite_code_on_user_insert on auth.users;

create trigger consume_invite_code_on_user_insert
before insert on auth.users
for each row
execute function public.consume_invite_code_on_user_insert();

revoke all on function public.consume_invite_code_on_user_insert() from public;

create or replace function public.activate_with_single_use_invite(
  p_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  submitted_code text;
  current_metadata jsonb;
  inviter_id uuid;
  inviter_metadata jsonb;
  candidate_code text;
  own_code text;
begin
  if current_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  submitted_code := upper(nullif(trim(coalesce(p_invite_code, '')), ''));
  if submitted_code is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_invite_code');
  end if;

  perform pg_catalog.pg_advisory_xact_lock(8675309::bigint);

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

  select id, raw_user_meta_data
  into inviter_id, inviter_metadata
  from auth.users
  where id <> current_user_id
    and upper(trim(coalesce(raw_user_meta_data ->> 'invite_code', ''))) =
      submitted_code
  for update;

  if inviter_id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_invite_code');
  end if;

  own_code := upper(
    nullif(trim(coalesce(current_metadata ->> 'invite_code', '')), '')
  );

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

  update auth.users
  set raw_user_meta_data = jsonb_set(
    coalesce(current_metadata, '{}'::jsonb)
      - 'needs_invite'
      - 'invited_by_code',
    '{invite_code}',
    to_jsonb(own_code),
    true
  ) || jsonb_build_object('needs_invite', false, 'invited_by_user_id', inviter_id::text)
  where id = current_user_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.activate_with_single_use_invite(text) from public;
grant execute on function public.activate_with_single_use_invite(text)
  to authenticated;
