alter table public.messages
  add column if not exists sender_is_channel boolean not null default false;

create or replace function public.guard_channel_message_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  room_type text;
begin
  select type
  into room_type
  from public.rooms
  where id = new.room_id;

  if room_type = 'channel'
    and (
      new.profile_id is distinct from auth.uid()
      or not exists (
        select 1
        from public.room_participants as participant
        where participant.room_id = new.room_id
          and participant.user_id = auth.uid()
          and participant.role in ('owner', 'admin')
      )
    ) then
    raise exception 'Only channel admins can publish messages'
      using errcode = '42501';
  end if;

  if coalesce(new.sender_is_channel, false) and room_type <> 'channel' then
    raise exception 'Channel identity can only be used in a channel'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'channel_avatars',
  'channel_avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = true,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "Anyone can view channel avatars" on storage.objects;
create policy "Anyone can view channel avatars"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'channel_avatars');

drop policy if exists "Users can upload their channel avatars" on storage.objects;
create policy "Users can upload their channel avatars"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'channel_avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );