drop policy if exists "Users can delete their own stories"
  on public.stories;
create policy "Users can delete their own stories"
  on public.stories
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

grant delete on public.stories to authenticated;
