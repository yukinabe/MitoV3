-- Mito V3 — pre-waitlist database hygiene
--
-- Cleans up the items the Supabase advisors flagged before a larger invite
-- wave. None of this blocks a tiny private test; do it before scaling.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- (The app's publishable key cannot run DDL.) Additive / idempotent.

-- 1) Foreign-key indexes -----------------------------------------------------
-- The performance advisor flagged FKs without a covering index. These speed up
-- joins and the ON DELETE CASCADE cleanups, and are safe no-ops if they exist.
create index if not exists decks_owner_idx               on public.decks (owner_user_id);
create index if not exists cards_deck_idx                on public.cards (deck_id);
create index if not exists cards_creator_idx             on public.cards (creator_id);
create index if not exists study_sessions_user_idx       on public.study_sessions (user_id);
create index if not exists character_progress_user_idx   on public.character_progress (user_id);
create index if not exists card_states_card_idx          on public.card_states (card_id);

-- 2) Function search_path ----------------------------------------------------
-- The security advisor flagged a mutable search_path on this trigger function.
-- Pin it to empty (pg_catalog stays implicitly available, so now() still
-- resolves) and mark it SECURITY DEFINER-safe. Trigger binding is preserved by
-- CREATE OR REPLACE.
create or replace function public.touch_card_states_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

-- 3) Manual dashboard steps (cannot be scripted via SQL) ---------------------
-- a) Leaked-password protection: Dashboard → Authentication → Providers →
--    Email → enable "Leaked password protection" (checks Have I Been Pwned).
-- b) Anonymous-access policy warnings: every app table already enforces
--    owner RLS (auth.uid() = user_id). The advisor warns because the `anon`
--    role *can* satisfy those policies once a row is anon-owned, which is by
--    design here (silent anonymous auth backs offline play). Review each table
--    in Dashboard → Authentication → Policies and confirm there is NO policy
--    with `using (true)` / `to anon` that would expose other users' rows.
--    `events`, `waitlist`, `card_states`, `character_progress` are all
--    owner-scoped; no public read should exist.
