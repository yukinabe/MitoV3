-- Mito V3 — waitlist / invite capture
--
-- PR-3: a private-beta gate. Captures email, referral source, invite code, and
-- a cohort label per (anonymous or signed-in) user so we can run invite waves
-- and see where signups come from.
--
-- The app always has a session (silent anonymous auth on launch), so this is
-- keyed by the auth user and protected by ordinary owner RLS — no public
-- anonymous-insert policy needed.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- (The app's publishable key cannot run DDL.) Additive / idempotent.

create table if not exists public.waitlist (
    user_id         uuid primary key references auth.users (id) on delete cascade,
    email           text,
    referral_source text,
    invite_code     text,
    cohort          text not null default 'waitlist',
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index if not exists waitlist_cohort_idx on public.waitlist (cohort);
create index if not exists waitlist_created_idx on public.waitlist (created_at desc);

alter table public.waitlist enable row level security;

drop policy if exists "waitlist is private to owner" on public.waitlist;
create policy "waitlist is private to owner"
    on public.waitlist
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
