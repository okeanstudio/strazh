create or replace function public.prevent_forwarded_message_edit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.forwarded_from_user_id is not null and (
    new.forwarded_from_user_id is distinct from old.forwarded_from_user_id
    or new.forwarded_from_name is distinct from old.forwarded_from_name
    or new.encrypted_content is distinct from old.encrypted_content
    or new.encrypted_content_type is distinct from old.encrypted_content_type
    or new.image_caption is distinct from old.image_caption
    or new.file_name is distinct from old.file_name
    or new.file_url is distinct from old.file_url
    or new.file_size is distinct from old.file_size
    or new.file_mime_type is distinct from old.file_mime_type
    or new.voice_url is distinct from old.voice_url
    or new.voice_duration is distinct from old.voice_duration
    or new.is_image is distinct from old.is_image
    or new.is_file is distinct from old.is_file
    or new.is_voice is distinct from old.is_voice
  ) then
    raise exception 'Forwarded messages cannot be edited';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_forwarded_message_edit() from public;

drop trigger if exists protect_forwarded_message_edits on public.messages;
create trigger protect_forwarded_message_edits
  before update on public.messages
  for each row execute function public.prevent_forwarded_message_edit();