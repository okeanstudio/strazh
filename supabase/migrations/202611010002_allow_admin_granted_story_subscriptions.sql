create or replace function public.create_text_story(
  p_content text,
  p_background_color text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  author auth.users%rowtype;
  story public.stories%rowtype;
  content_text text := btrim(coalesce(p_content, ''));
  background text := coalesce(p_background_color, '');
  expires_text text;
  expires_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if char_length(content_text) < 1 or char_length(content_text) > 500 then
    raise exception 'Story text must contain between 1 and 500 characters'
      using errcode = '22023';
  end if;

  if background !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Invalid story background color'
      using errcode = '22023';
  end if;

  select *
  into author
  from auth.users
  where id = auth.uid()
  for update;

  if not found then
    raise exception 'User not found'
      using errcode = 'P0002';
  end if;

  if coalesce(author.raw_user_meta_data ->> 'subscription_type', '') <> 'premium' then
    raise exception 'Strazh Infinity subscription is required'
      using errcode = '42501';
  end if;

  expires_text := author.raw_user_meta_data ->> 'subscription_expires_at';
  if lower(coalesce(expires_text, '')) <> 'forever' then
    begin
      expires_at := expires_text::timestamptz;
    exception when others then
      expires_at := null;
    end;

    if expires_at is null or expires_at <= now() then
      raise exception 'An active Strazh Infinity subscription is required'
        using errcode = '42501';
    end if;
  end if;

  insert into public.stories (
    user_id,
    author_name,
    author_tag,
    author_avatar_url,
    content,
    background_color
  )
  values (
    author.id,
    coalesce(
      nullif(author.raw_user_meta_data ->> 'name', ''),
      nullif(author.raw_user_meta_data ->> 'full_name', ''),
      nullif(author.raw_user_meta_data ->> 'tag', ''),
      'Пользователь'
    ),
    coalesce(author.raw_user_meta_data ->> 'tag', ''),
    author.raw_user_meta_data ->> 'avatar_url',
    content_text,
    background
  )
  returning * into story;

  return to_jsonb(story);
end;
$$;

revoke all on function public.create_text_story(text, text) from public, anon;
grant execute on function public.create_text_story(text, text) to authenticated;
