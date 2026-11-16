drop function if exists public.verify_phone_login_message(uuid, text);

create function public.verify_phone_login_message(
  p_request_id uuid,
  p_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  challenge public.phone_login_challenges%rowtype;
begin
  select *
  into challenge
  from public.phone_login_challenges
  where id = p_request_id
  for update;

  if not found
    or challenge.consumed_at is not null
    or challenge.expires_at <= now()
    or challenge.attempts >= 5 then
    return null;
  end if;

  if challenge.login_code is distinct from p_code then
    update public.phone_login_challenges
    set attempts = attempts + 1
    where id = p_request_id;
    return null;
  end if;

  update public.phone_login_challenges
  set consumed_at = now()
  where id = p_request_id;

  return challenge.user_id;
end;
$$;

revoke all on function public.verify_phone_login_message(uuid, text)
  from public;
grant execute on function public.verify_phone_login_message(uuid, text)
  to service_role;
