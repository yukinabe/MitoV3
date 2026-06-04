-- Mito V3 — FSRS scheduling state
--
-- Per-user, per-card spaced-repetition state for the FSRS-6 scheduler
-- (see MitoV3/Models.swift). Cards are shared content (decks can belong to a
-- room), but *scheduling* is personal, so it lives in its own table keyed by
-- (user_id, card_id) — the same separation Anki uses between notes and reviews.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- (The app's publishable key cannot run DDL, so this one step is manual.)

create extension if not exists "pgcrypto";

create table if not exists public.card_states (
    id           uuid primary key default gen_random_uuid(),
    user_id      uuid not null references auth.users (id) on delete cascade,
    card_id      uuid not null references public.cards (id) on delete cascade,

    -- FSRS latent state. stability/difficulty are null until the first review.
    stability    double precision,
    difficulty   double precision,
    phase        smallint     not null default 0,   -- 0 new · 1 learning · 2 review · 3 relearning
    due          timestamptz  not null default now(),
    last_review  timestamptz,
    reps         integer      not null default 0,
    lapses       integer      not null default 0,

    updated_at   timestamptz  not null default now(),

    unique (user_id, card_id)
);

-- Fast "what's due for me" lookups.
create index if not exists card_states_user_due_idx
    on public.card_states (user_id, due);

-- Keep updated_at fresh on every upsert.
create or replace function public.touch_card_states_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists card_states_touch on public.card_states;
create trigger card_states_touch
    before update on public.card_states
    for each row execute function public.touch_card_states_updated_at();

-- Row-level security: a user can only see and write their own scheduling state.
alter table public.card_states enable row level security;

drop policy if exists "card_states are private to owner" on public.card_states;
create policy "card_states are private to owner"
    on public.card_states
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
