create or replace function public.update_my_bot(
  p_bot_id uuid,
  p_field text,
  p_value text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_value text := btrim(coalesce(p_value, ''));
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_field is null or p_field not in ('name', 'description', 'tag') then
    raise exception 'unsupported bot setting';
  end if;
  if p_field in ('name', 'tag') and v_value = '' then
    raise exception 'this bot setting cannot be empty';
  end if;

  if p_field = 'tag' then
    v_value := lower(regexp_replace(v_value, '^@+', '', 'g'));
    if v_value !~ '^[a-z0-9_]{3,32}$' or v_value !~ 'bot$' then
      raise exception 'bot username must contain 3-32 letters, numbers or underscores and end with bot';
    end if;
    if v_value = 'botfather' then
      raise exception 'this username is reserved';
    end if;
  end if;

  update public.bots
  set name = case when p_field = 'name' then v_value else name end,
      description = case
        when p_field = 'description' then v_value
        else description
      end,
      tag = case when p_field = 'tag' then v_value else tag end,
      updated_at = now()
  where id = p_bot_id
    and owner_id = auth.uid()
    and not is_system;

  if not found then
    raise exception 'bot not found or access denied';
  end if;
end;
$$;

revoke all on function public.update_my_bot(uuid, text, text)
  from public, anon;
grant execute on function public.update_my_bot(uuid, text, text)
  to authenticated;
