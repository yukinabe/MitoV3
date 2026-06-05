-- Mito V3 — wallet persistence + activation events
--
-- PR-1 of the MVP-readiness work: make the study loop real and measurable.
--   1. Persist each player's wallet on their profile (was demo-only, in-memory).
--   2. Log activation events (app open, study start/end, card created, review
--      graded, battle wave cleared, deck imported) so we can answer
--      "are users studying?" and "does battle bring them back?".
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- (The app's publishable key cannot run DDL, so this one step is manual.)
-- All statements are additive / idempotent and safe to re-run.

-- 1) Wallet columns on the existing profiles table. Assumes profiles.id is the
--    auth user id (standard Supabase pattern). Defaults to 0 — new players start
--    empty and earn their way up.
alter table public.profiles add column if not exists atp     integer not null default 0;
alter table public.profiles add column if not exists gold    integer not null default 0;
alter table public.profiles add column if not exists gems    integer not null default 0;
alter table public.profiles add column if not exists biomass integer not null default 0;
alter table public.profiles add column if not exists shards  integer not null default 0;

-- 2) Generic activation event log. props holds event-specific fields as JSON so
--    we can add new event types without migrations.
create table if not exists public.events (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users (id) on delete cascade,
    name        text not null,
    props       jsonb not null default '{}'::jsonb,
    created_at  timestamptz not null default now()
);

-- Fast "events for this user, newest first" and per-type funnels.
create index if not exists events_user_created_idx on public.events (user_id, created_at desc);
create index if not exists events_name_idx          on public.events (name);

alter table public.events enable row level security;

drop policy if exists "events are private to owner" on public.events;
create policy "events are private to owner"
    on public.events
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
