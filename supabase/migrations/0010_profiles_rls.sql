-- Mito V3 — profiles RLS (owner self-service)
--
-- The app creates/updates its own profile row client-side via an upsert
-- (MitoBackend.upsertProfile). The profiles table had RLS enabled but no INSERT
-- policy, so anonymous sign-in failed with 42501 ("new row violates row-level
-- security policy for table profiles") and the whole app silently fell back to
-- offline — which also disabled the AI grader, friends, lobbies, etc.
--
-- This adds owner-scoped select/insert/update policies so a user can manage
-- exactly their own profile. Friends still read each other's names through the
-- security-definer RPCs (find_profile_by_friend_code / get_friends), so this
-- does NOT expose other people's profiles.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

alter table public.profiles enable row level security;

drop policy if exists "profiles: owner can read" on public.profiles;
create policy "profiles: owner can read"
    on public.profiles for select
    using (auth.uid() = id);

drop policy if exists "profiles: owner can insert" on public.profiles;
create policy "profiles: owner can insert"
    on public.profiles for insert
    with check (auth.uid() = id);

drop policy if exists "profiles: owner can update" on public.profiles;
create policy "profiles: owner can update"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);
