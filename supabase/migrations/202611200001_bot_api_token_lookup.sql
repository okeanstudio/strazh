drop function if exists public.find_bot_by_token(text);

create function public.find_bot_by_token(p_token_hash text)
returns table (
  id uuid,
  owner_id uuid,
  name text,
  tag text,
  description text,
  avatar_url text,
  is_verified boolean,
  is_enabled boolean
)
language sql
security definer
set search_path = public
as $$
  select
    bot.id,
    bot.owner_id,
    bot.name,
    bot.tag,
    bot.description,
    bot.avatar_url,
    bot.is_verified,
    bot.is_enabled
  from public.bots as bot
  where bot.token_hash = p_token_hash
    and bot.is_enabled;
$$;

revoke all on function public.find_bot_by_token(text)
  from public, anon, authenticated;
grant execute on function public.find_bot_by_token(text) to service_role;

notify pgrst, 'reload schema';
