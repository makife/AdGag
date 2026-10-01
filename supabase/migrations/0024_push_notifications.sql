-- ============================================================================
-- 0024_push_notifications.sql
-- Push delivery for the in-app notifications (CLAUDE.md section 32).
--
--  * device_tokens: + locale (the push is written in the language the app
--    shows on that device) and updated_at; register/unregister RPCs. A
--    token belongs to ONE user: registering it moves it away from whoever
--    used the device before (shared phone, sign-out/sign-in).
--  * notification_preferences: per-user switches, read by the send-push
--    Edge Function. No row = everything on. The in-app list is unaffected.
--  * Every new notifications row is handed to the send-push Edge Function
--    through pg_net (asynchronous: sent after the transaction commits,
--    never slows or breaks the action that caused it). The function URL
--    and the shared secret live in Supabase Vault (names below), set once
--    outside migrations — without them nothing is sent.
-- ============================================================================

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------- tokens
alter table public.device_tokens
  add column if not exists locale text not null default 'en',
  add column if not exists updated_at timestamptz not null default now();

create index if not exists device_tokens_token_idx on public.device_tokens (token);

create or replace function public.register_device_token(p_token text, p_platform text, p_locale text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;
  if p_platform not in ('ios', 'android') or length(coalesce(p_token, '')) not between 10 and 4096 then
    raise exception 'Invalid device token' using errcode = '22023';
  end if;
  -- The device now belongs to this user.
  delete from public.device_tokens where token = p_token and user_id <> uid;
  insert into public.device_tokens (user_id, platform, token, locale)
  values (uid, p_platform, p_token, left(coalesce(nullif(p_locale, ''), 'en'), 8))
  on conflict (user_id, token) do update
    set platform = excluded.platform, locale = excluded.locale, updated_at = now();
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_device_token(text, text, text) from public, anon;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.register_device_token(text, text, text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;

-- ----------------------------------------------------------- preferences
create table public.notification_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  new_followers boolean not null default true,
  reviews boolean not null default true,      -- new_review + review_reply
  mentions boolean not null default true,
  ad_this boolean not null default true,
  updated_at timestamptz not null default now()
);

comment on table public.notification_preferences is
  'Which notification types are PUSHED to the user''s devices (no row = all). The in-app list always gets everything.';

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;

create policy notification_preferences_select_own
  on public.notification_preferences for select using (auth.uid() = user_id);
create policy notification_preferences_insert_own
  on public.notification_preferences for insert with check (auth.uid() = user_id);
create policy notification_preferences_update_own
  on public.notification_preferences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

revoke all on public.notification_preferences from anon;
grant select, insert, update on public.notification_preferences to authenticated;

-- -------------------------------------------------------------- dispatch
create or replace function public.dispatch_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text;
  fn_secret text;
begin
  select decrypted_secret into fn_url from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into fn_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if fn_url is null or fn_secret is null then
    return new;  -- push not configured on this project
  end if;
  perform net.http_post(
    url := fn_url,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', fn_secret),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  -- A push problem must never undo the follow/review/Ad that caused it.
  raise warning 'push dispatch failed: %', sqlerrm;
  return new;
end;
$$;

revoke all on function public.dispatch_push_notification() from public, anon, authenticated;

create trigger notifications_dispatch_push
  after insert on public.notifications
  for each row
  execute function public.dispatch_push_notification();
