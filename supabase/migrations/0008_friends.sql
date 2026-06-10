-- Mito V3 — friends
--
-- A friend graph for the social/co-op/PvP features. Each profile gets a short
-- shareable friend code; friendships are one row per relationship with a status.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

-- 1) Short, shareable friend code on every profile.
alter table public.profiles
    add column if not exists friend_code text;

-- Backfill + default a 6-char code (uppercase, ambiguity-free alphabet).
create or replace function public.gen_friend_code()
returns text language sql volatile as $$
    select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789',
                             (floor(random()*30)+1)::int, 1), '')
    from generate_series(1, 6);
$$;

update public.profiles set friend_code = public.gen_friend_code()
    where friend_code is null;

create unique index if not exists profiles_friend_code_idx
    on public.profiles (friend_code);

-- 2) Friendships. One row per relationship; either party can read it, the
--    addressee flips status to 'accepted'.
create table if not exists public.friendships (
    id          uuid primary key default gen_random_uuid(),
    requester   uuid not null references auth.users (id) on delete cascade,
    addressee   uuid not null references auth.users (id) on delete cascade,
    status      text not null default 'pending' check (status in ('pending','accepted')),
    created_at  timestamptz not null default now(),
    unique (requester, addressee),
    check (requester <> addressee)
);

create index if not exists friendships_requester_idx on public.friendships (requester);
create index if not exists friendships_addressee_idx on public.friendships (addressee);

alter table public.friendships enable row level security;

-- You can see any friendship row you're part of.
drop policy if exists "friendships visible to either party" on public.friendships;
create policy "friendships visible to either party"
    on public.friendships for select
    using (auth.uid() = requester or auth.uid() = addressee);

-- You can send a request (as the requester).
drop policy if exists "send friend request" on public.friendships;
create policy "send friend request"
    on public.friendships for insert
    with check (auth.uid() = requester);

-- The addressee can accept (update status); either party can delete (unfriend/cancel).
drop policy if exists "addressee updates friendship" on public.friendships;
create policy "addressee updates friendship"
    on public.friendships for update
    using (auth.uid() = addressee or auth.uid() = requester)
    with check (auth.uid() = addressee or auth.uid() = requester);

drop policy if exists "either party removes friendship" on public.friendships;
create policy "either party removes friendship"
    on public.friendships for delete
    using (auth.uid() = requester or auth.uid() = addressee);

-- Allow looking a friend up by their code (read-only single-column exposure via
-- a security-definer RPC, so we don't open the whole profiles table).
create or replace function public.find_profile_by_friend_code(code text)
returns table (id uuid, display_name text, friend_code text)
language sql security definer set search_path = public as $$
    select id, display_name, friend_code
    from public.profiles
    where friend_code = upper(code)
    limit 1;
$$;

-- All of my relationships (accepted + pending) with the other party's display
-- name and the direction, so the client can split friends / incoming / outgoing
-- without opening the whole profiles table to reads.
create or replace function public.get_friends()
returns table (friend_id uuid, display_name text, friend_code text, status text, direction text)
language sql security definer set search_path = public as $$
    select
        case when f.requester = auth.uid() then f.addressee else f.requester end as friend_id,
        p.display_name,
        p.friend_code,
        f.status,
        case when f.requester = auth.uid() then 'outgoing' else 'incoming' end as direction
    from public.friendships f
    join public.profiles p
      on p.id = (case when f.requester = auth.uid() then f.addressee else f.requester end)
    where f.requester = auth.uid() or f.addressee = auth.uid();
$$;
