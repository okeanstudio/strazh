create table if not exists public.user_profile_nft_decorations (
  user_id uuid not null references auth.users(id) on delete cascade,
  placement text not null check (placement in ('avatar', 'name')),
  slot smallint not null,
  gift_inventory_id uuid not null
    references public.user_gift_inventory(id) on delete cascade,
  primary key (user_id, placement, slot),
  unique (gift_inventory_id),
  check (
    (placement = 'avatar' and slot between 0 and 3)
    or (placement = 'name' and slot = 0)
  )
);

alter table public.user_profile_nft_decorations enable row level security;
revoke all on public.user_profile_nft_decorations from public, anon, authenticated;
grant select on public.user_profile_nft_decorations to authenticated;

drop policy if exists "Authenticated users can view profile NFT decorations"
  on public.user_profile_nft_decorations;
create policy "Authenticated users can view profile NFT decorations"
  on public.user_profile_nft_decorations
  for select
  to authenticated
  using (auth.uid() is not null);

create or replace function public.set_user_profile_nft_decoration(
  p_placement text,
  p_slot smallint,
  p_inventory_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_placement not in ('avatar', 'name')
    or (p_placement = 'avatar' and p_slot not between 0 and 3)
    or (p_placement = 'name' and p_slot <> 0) then
    raise exception 'Invalid decoration placement'
      using errcode = '22023';
  end if;

  if p_inventory_id is not null and not exists (
    select 1
    from public.user_gift_inventory as inventory
    where inventory.id = p_inventory_id
      and inventory.recipient_id = auth.uid()
      and inventory.nft_serial is not null
  ) then
    raise exception 'Only owned NFT gifts can decorate a profile'
      using errcode = '42501';
  end if;

  delete from public.user_profile_nft_decorations as decoration
  where decoration.user_id = auth.uid()
    and (
      (decoration.placement = p_placement and decoration.slot = p_slot)
      or decoration.gift_inventory_id = p_inventory_id
    );

  if p_inventory_id is not null then
    insert into public.user_profile_nft_decorations (
      user_id,
      placement,
      slot,
      gift_inventory_id
    )
    values (auth.uid(), p_placement, p_slot, p_inventory_id);
  end if;
end;
$$;

revoke all on function public.set_user_profile_nft_decoration(text, smallint, uuid)
  from public, anon;
grant execute on function public.set_user_profile_nft_decoration(text, smallint, uuid)
  to authenticated;
