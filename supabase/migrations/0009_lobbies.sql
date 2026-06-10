-- Mito V3 — lobbies (co-op + PvP)
--
-- A lobby is a short-coded room a friend can join. Co-op and PvP both ride on
-- it. Live state (who's present, their characters, in-match moves) is carried by
-- Supabase Realtime channels keyed by the lobby code; these tables hold the
-- durable bits (membership, match results).
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

create table if not exists public.lobbies (
    id          uuid primary key default gen_random_uuid(),
    code        text not null unique,
    host        uuid not null references auth.users (id) on delete cascade,
    mode        text not null default 'coop' check (mode in ('coop','pvp')),
    deck_id     uuid,                      -- chosen deck for PvP duels
    status      text not null default 'open' check (status in ('open','in_progress','closed')),
    created_at  timestamptz not null default now()
);

create table if not exists public.lobby_members (
    lobby_id      uuid not null references public.lobbies (id) on delete cascade,
    user_id       uuid not null references auth.users (id) on delete cascade,
    character_ids jsonb not null default '[]'::jsonb,  -- their active party, to spawn for everyone
    ready         boolean not null default false,
    joined_at     timestamptz not null default now(),
    primary key (lobby_id, user_id)
);

-- Optional durable PvP results (no FSRS impact; just bragging rights / stats).
create table if not exists public.pvp_matches (
    id          uuid primary key default gen_random_uuid(),
    lobby_id    uuid references public.lobbies (id) on delete set null,
    deck_id     uuid,
    player_a    uuid references auth.users (id) on delete set null,
    player_b    uuid references auth.users (id) on delete set null,
    winner      uuid references auth.users (id) on delete set null,
    created_at  timestamptz not null default now()
);

create index if not exists lobby_members_user_idx on public.lobby_members (user_id);
create index if not exists lobbies_code_idx on public.lobbies (code);

alter table public.lobbies enable row level security;
alter table public.lobby_members enable row level security;
alter table public.pvp_matches enable row level security;

-- A user can see a lobby if they're the host or a member.
drop policy if exists "lobby visible to members" on public.lobbies;
create policy "lobby visible to members" on public.lobbies for select
    using (
        host = auth.uid()
        or exists (select 1 from public.lobby_members m
                   where m.lobby_id = lobbies.id and m.user_id = auth.uid())
    );

drop policy if exists "host creates lobby" on public.lobbies;
create policy "host creates lobby" on public.lobbies for insert
    with check (host = auth.uid());

drop policy if exists "host updates lobby" on public.lobbies;
create policy "host updates lobby" on public.lobbies for update
    using (host = auth.uid()) with check (host = auth.uid());

drop policy if exists "host closes lobby" on public.lobbies;
create policy "host closes lobby" on public.lobbies for delete
    using (host = auth.uid());

-- Membership: you manage your own row; members can read the roster of a lobby
-- they belong to.
drop policy if exists "see lobby roster" on public.lobby_members;
create policy "see lobby roster" on public.lobby_members for select
    using (
        user_id = auth.uid()
        or exists (select 1 from public.lobby_members m
                   where m.lobby_id = lobby_members.lobby_id and m.user_id = auth.uid())
    );

drop policy if exists "join lobby" on public.lobby_members;
create policy "join lobby" on public.lobby_members for insert
    with check (user_id = auth.uid());

drop policy if exists "update my membership" on public.lobby_members;
create policy "update my membership" on public.lobby_members for update
    using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "leave lobby" on public.lobby_members;
create policy "leave lobby" on public.lobby_members for delete
    using (user_id = auth.uid());

drop policy if exists "pvp results visible to players" on public.pvp_matches;
create policy "pvp results visible to players" on public.pvp_matches for select
    using (player_a = auth.uid() or player_b = auth.uid());

drop policy if exists "players record pvp result" on public.pvp_matches;
create policy "players record pvp result" on public.pvp_matches for insert
    with check (player_a = auth.uid() or player_b = auth.uid());

-- Join a lobby by code in one round-trip: returns the lobby id (or null).
create or replace function public.join_lobby(p_code text, p_character_ids jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
    select id into v_id from public.lobbies where code = upper(p_code) and status = 'open';
    if v_id is null then return null; end if;
    insert into public.lobby_members (lobby_id, user_id, character_ids)
    values (v_id, auth.uid(), coalesce(p_character_ids, '[]'::jsonb))
    on conflict (lobby_id, user_id) do update set character_ids = excluded.character_ids;
    return v_id;
end;
$$;
