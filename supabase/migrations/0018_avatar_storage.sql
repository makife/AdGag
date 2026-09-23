-- ============================================================================
-- 0018_avatar_storage.sql
-- Avatar upload (CLAUDE.md section 13/24 — `avatar_url` was always a
-- `profiles` column, but no upload path existed until now). Public bucket:
-- avatars are already public-facing data (profiles_select_public exposes
-- avatar_url to anyone), so this doesn't expose anything RLS on `profiles`
-- didn't already.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Path convention: `{user_id}/avatar.<ext>` — the folder name IS the
-- owner's auth uid, so ownership is checkable from the path alone without
-- a separate owner column/lookup.
create policy avatars_public_read
  on storage.objects
  for select
  using (bucket_id = 'avatars');

create policy avatars_owner_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_owner_update
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy avatars_owner_delete
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
