alter table public.rooms
  add column if not exists is_private boolean not null default false;

create or replace function public.guard_private_group_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.rooms as room
    where room.id = new.room_id
      and room.type = 'group'
      and room.is_private
      and room.created_by is distinct from auth.uid()
  ) then
    raise exception 'Private groups can only be joined by invitation'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_private_group_membership
  on public.room_participants;
create trigger guard_private_group_membership
  before insert on public.room_participants
  for each row execute function public.guard_private_group_membership();