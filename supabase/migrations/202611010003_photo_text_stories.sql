alter table public.stories
  add column if not exists image_url text;

alter table public.stories
  drop constraint if exists stories_content_check;

alter table public.stories
  add constraint stories_content_check
  check (
    char_length(btrim(content)) between 0 and 500
    and (char_length(btrim(content)) > 0 or image_url is not null)
  );

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'stories',
  'stories',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set public = false,
    file_size_limit = 8388608,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic'];

drop policy if exists "Users can view active story photos" on storage.objects;
create policy "Users can view active story photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'stories'
    and exists (
      select 1
      from public.stories as story
      where story.image_url = storage.objects.name
        and story.expires_at > now()
    )
  );

drop policy if exists "Users can upload their own story photos" on storage.objects;
create policy "Users can upload their own story photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'stories'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop function if exists public.create_text_story(text, text);

create or replace function public.create_text_story(
  p_content text,
  p_background_color text,
  p_image_url text
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

  if char_length(content_text) > 500
    or (char_length(content_text) = 0 and p_image_url is null) then
    raise exception 'A story needs a photo or text up to 500 characters'
      using errcode = '22023';
  end if;

  if background !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Invalid story background color'
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
    image_url,
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
    p_image_url,
    background
  )
  returning * into story;

  return to_jsonb(story);
end;
$$;

revoke all on function public.create_text_story(text, text, text)
  from public, anon;
grant execute on function public.create_text_story(text, text, text)
  to authenticated;
