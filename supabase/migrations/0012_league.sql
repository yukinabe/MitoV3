-- Mito V3 — weekly friends league
--
-- A friends-only leaderboard of focus minutes for the current ISO week
-- (resets Monday 00:00 server time). Friends-only keeps it social-accountable
-- and cheat-resistant; only accepted friendships are visible.
--
-- Reads study_sessions, which was created via the dashboard. This assumes its
-- row-creation timestamp column is `created_at` (default now()); if your
-- column is named differently (e.g. inserted_at), adjust the filter below.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

create or replace function public.get_friend_league()
returns table (user_id uuid, display_name text, minutes bigint, is_me boolean)
language sql security definer set search_path = public as $$
    with circle as (
        select auth.uid() as uid
        union
        select case when f.requester = auth.uid() then f.addressee else f.requester end
        from public.friendships f
        where (f.requester = auth.uid() or f.addressee = auth.uid())
          and f.status = 'accepted'
    )
    select
        c.uid as user_id,
        coalesce(p.display_name, 'Scholar') as display_name,
        coalesce(sum(s.duration_minutes)
                 filter (where s.created_at >= date_trunc('week', now())), 0)::bigint as minutes,
        (c.uid = auth.uid()) as is_me
    from circle c
    left join public.profiles p on p.id = c.uid
    left join public.study_sessions s on s.user_id = c.uid
    where c.uid is not null
    group by c.uid, p.display_name
    order by minutes desc, display_name;
$$;

revoke execute on function public.get_friend_league() from public, anon;
grant execute on function public.get_friend_league() to authenticated;
