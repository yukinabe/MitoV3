-- Mito V3 — per-user character levels and stats
--
-- Characters are global game content, but upgrades are personal. This table
-- stores each user's current level/stat state for each character id.

create table if not exists public.character_progress (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid        not null references auth.users (id) on delete cascade,
    character_id   text        not null,

    level          integer     not null,
    hp             integer     not null,
    attack         integer     not null,
    defense        integer     not null,

    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),

    unique (user_id, character_id),
    constraint character_progress_level_positive check (level >= 1),
    constraint character_progress_hp_positive check (hp >= 1),
    constraint character_progress_attack_nonnegative check (attack >= 0),
    constraint character_progress_defense_nonnegative check (defense >= 0)
);

create index if not exists character_progress_user_idx
    on public.character_progress (user_id);

create or replace function public.touch_character_progress_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists character_progress_touch on public.character_progress;
create trigger character_progress_touch
    before update on public.character_progress
    for each row execute function public.touch_character_progress_updated_at();

alter table public.character_progress enable row level security;

drop policy if exists "character_progress is private to owner" on public.character_progress;
create policy "character_progress is private to owner"
    on public.character_progress
    for all
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
