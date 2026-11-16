drop policy if exists "Users can read own additional usernames"
  on public.user_additional_usernames;
create policy "Users can read additional usernames"
  on public.user_additional_usernames
  for select
  to authenticated
  using (true);
