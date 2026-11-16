drop policy if exists "Authenticated users can view active stories"
  on public.stories;
drop policy if exists "Authenticated users can view all stories"
  on public.stories;
create policy "Authenticated users can view all stories"
  on public.stories
  for select
  to authenticated
  using (true);

drop policy if exists "Users can view active story photos"
  on storage.objects;
drop policy if exists "Users can view story photos"
  on storage.objects;
create policy "Users can view story photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'stories'
    and exists (
      select 1
      from public.stories as story
      where story.image_url = storage.objects.name
    )
  );
