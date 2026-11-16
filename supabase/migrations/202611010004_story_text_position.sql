alter table public.stories
  add column if not exists text_position_x double precision not null default 0.5
    check (text_position_x between 0 and 1),
  add column if not exists text_position_y double precision not null default 0.5
    check (text_position_y between 0 and 1);

create or replace function public.create_text_story(
  p_content text,
  p_background_color text,
  p_image_url text,
  p_text_position_x double precision,
  p_text_position_y double precision
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
  subscription_type text;
  subscription_plan_id text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if char_length(content_text) > 500
    or (char_length(content_text) = 0 and p_image_url is null) then
    raise exception 'A story needs a photo or text up to 500 characters'
      using errcode = '22023';
  end if;

  if background !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Invalid story background color'
      using errcode = '22023';
  end if;

  if p_text_position_x is null
    or p_text_position_x not between 0 and 1
    or p_text_position_y is null
    or p_text_position_y not between 0 and 1 then
    raise exception 'Invalid story text position'
      using errcode = '22023';
  end if;

  if p_image_url is not null
    and p_image_url !~ (
      '^' || auth.uid()::text || '/[0-9]+[.](jpg|jpeg|png|webp|heic)$'
    ) then
    raise exception 'Invalid story photo path'
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

  subscription_type := lower(btrim(coalesce(
    author.raw_user_meta_data ->> 'subscription_type',
    ''
  )));
  subscription_plan_id := lower(btrim(coalesce(
    author.raw_user_meta_data ->> 'subscription_plan_id',
    ''
  )));
  if subscription_type <> 'premium' and subscription_plan_id <> 'forever' then
    raise exception 'Strazh Infinity subscription is required'
      using errcode = '42501';
  end if;

  expires_text := btrim(coalesce(
    author.raw_user_meta_data ->> 'subscription_expires_at',
    ''
  ));
  if lower(expires_text) <> 'forever' and subscription_plan_id <> 'forever' then
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
    image_url,
    background_color,
    text_position_x,
    text_position_y
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
    p_image_url,
    background,
    p_text_position_x,
    p_text_position_y
  )
  returning * into story;

  return to_jsonb(story);
end;
$$;

revoke all on function public.create_text_story(
  text,
  text,
  text,
  double precision,
  double precision
) from public, anon;
grant execute on function public.create_text_story(
  text,
  text,
  text,
  double precision,
  double precision
) to authenticated;
