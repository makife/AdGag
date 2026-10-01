-- ============================================================================
-- 0026_comment_likes_fk_to_auth_users.sql
--
-- 0025's comment_likes.user_id -> profiles made comment_likes a junction
-- between comments and profiles, so PostgREST could no longer resolve a
-- plain `comments?select=*,profiles(...)` embed (PGRST201, HTTP 300) — which
-- is exactly what every app build before 0.1.16 sends: their REVIEWS panel
-- broke the moment 0025 went live (caught by the live smoke test).
--
-- Point the FK at auth.users instead (profiles.id IS the auth user id, and
-- deleting a user still cascades): no comments<->profiles path through
-- comment_likes any more, so old builds work again. New builds name the
-- FK explicitly anyway (profiles!comments_user_id_fkey).
-- ============================================================================

alter table public.comment_likes drop constraint if exists comment_likes_user_id_fkey;

alter table public.comment_likes
  add constraint comment_likes_user_id_fkey
  foreign key (user_id) references auth.users (id) on delete cascade;
