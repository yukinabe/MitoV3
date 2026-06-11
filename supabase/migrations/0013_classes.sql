-- Mito V3 — classes (study groups with shared decks)
--
-- A "class" is a friend-group-style room a student creates and shares a code
-- for; classmates join and can share decks into a common shelf that anyone in
-- the class can copy into their own collection. This is the collaboration loop.
--
-- GATING (enforced client-side against the Mito+ flag; these RPCs only enforce
-- membership + a hard member cap as a safety net, since paid status isn't in
-- the DB until RevenueCat lands):
--   • Free: join up to 3 classes, create 1, classes capped at 30 members.
--   • Mito+: unlimited.
--
-- SECURITY MODEL: all four tables have RLS enabled with NO permissive policies,
-- so they're unreachable with the publishable key directly. Every access goes
-- through the security-definer RPCs below, each of which checks the caller's
-- membership via auth.uid(). Reuses gen_friend_code() from 0008 for join codes.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

create table if not exists public.classes (
    id          uuid primary key default gen_random_uuid(),
    code        text not null unique,
    name        text not null,
    owner       uuid not null references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now()
);

create table if not exists public.class_members (
    class_id   uuid not null references public.classes (id) on delete cascade,
    user_id    uuid not null references auth.users (id) on delete cascade,
    role       text not null default 'member' check (role in ('owner','member')),
    joined_at  timestamptz not null default now(),
    primary key (class_id, user_id)
);

create table if not exists public.class_decks (
    id              uuid primary key default gen_random_uuid(),
    class_id        uuid not null references public.classes (id) on delete cascade,
    shared_by       uuid references auth.users (id) on delete set null,
    shared_by_name  text,
    name            text not null,
    card_count      int not null default 0,
    created_at      timestamptz not null default now()
);

create table if not exists public.class_cards (
    id            uuid primary key default gen_random_uuid(),
    class_deck_id uuid not null references public.class_decks (id) on delete cascade,
    front         text not null,
    back          text not null,
    tags          text[] not null default '{}'
);

create index if not exists class_members_user_idx on public.class_members (user_id);
create index if not exists class_decks_class_idx  on public.class_decks (class_id);
create index if not exists class_cards_deck_idx   on public.class_cards (class_deck_id);

-- Lock every table down; the security-definer RPCs are the only way in.
alter table public.classes       enable row level security;
alter table public.class_members enable row level security;
alter table public.class_decks   enable row level security;
alter table public.class_cards   enable row level security;

-- 1) Create a class (becomes owner + first member). Code is unique + retried.
create or replace function public.create_class(p_name text)
returns table (id uuid, code text, name text)
language plpgsql security definer set search_path = public as $$
declare v_code text; v_id uuid;
begin
    if auth.uid() is null then raise exception 'not authenticated'; end if;
    loop
        v_code := public.gen_friend_code();
        exit when not exists (select 1 from public.classes c where c.code = v_code);
    end loop;
    insert into public.classes (code, name, owner)
        values (v_code, left(trim(p_name), 60), auth.uid())
        returning classes.id into v_id;
    insert into public.class_members (class_id, user_id, role)
        values (v_id, auth.uid(), 'owner');
    return query select c.id, c.code, c.name from public.classes c where c.id = v_id;
end; $$;

-- 2) Join a class by code. Returns the class (id,name), or no rows if the code
--    is unknown. Enforces the 30-member hard cap.
create or replace function public.join_class(p_code text)
returns table (id uuid, name text)
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_count int;
begin
    if auth.uid() is null then raise exception 'not authenticated'; end if;
    select c.id into v_id from public.classes c where c.code = upper(trim(p_code));
    if v_id is null then return; end if;
    if not exists (select 1 from public.class_members m
                   where m.class_id = v_id and m.user_id = auth.uid()) then
        select count(*) into v_count from public.class_members m where m.class_id = v_id;
        if v_count >= 30 then raise exception 'class full'; end if;
        insert into public.class_members (class_id, user_id) values (v_id, auth.uid())
            on conflict do nothing;
    end if;
    return query select c.id, c.name from public.classes c where c.id = v_id;
end; $$;

-- 3) All classes I'm in, with member counts + whether I own it.
create or replace function public.get_my_classes()
returns table (id uuid, code text, name text, owner uuid, member_count bigint, is_owner boolean)
language sql security definer set search_path = public as $$
    select c.id, c.code, c.name, c.owner,
        (select count(*) from public.class_members m2 where m2.class_id = c.id) as member_count,
        (c.owner = auth.uid()) as is_owner
    from public.classes c
    where exists (select 1 from public.class_members m
                  where m.class_id = c.id and m.user_id = auth.uid())
    order by c.created_at desc;
$$;

-- 4) Roster of a class I belong to.
create or replace function public.get_class_roster(p_class_id uuid)
returns table (user_id uuid, display_name text, role text)
language sql security definer set search_path = public as $$
    select m.user_id, coalesce(p.display_name, 'Scholar'), m.role
    from public.class_members m
    left join public.profiles p on p.id = m.user_id
    where m.class_id = p_class_id
      and exists (select 1 from public.class_members me
                  where me.class_id = p_class_id and me.user_id = auth.uid())
    order by (m.role = 'owner') desc, p.display_name;
$$;

-- 5) Leave a class. If the owner leaves, the class (and its decks) is deleted.
create or replace function public.leave_class(p_class_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
    if exists (select 1 from public.classes c
               where c.id = p_class_id and c.owner = auth.uid()) then
        delete from public.classes where id = p_class_id;
    else
        delete from public.class_members
            where class_id = p_class_id and user_id = auth.uid();
    end if;
end; $$;

-- 6) Share a deck snapshot into a class (caller must be a member).
create or replace function public.share_deck_to_class(p_class_id uuid, p_name text, p_cards jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_deck_id uuid; v_name text;
begin
    if not exists (select 1 from public.class_members m
                   where m.class_id = p_class_id and m.user_id = auth.uid()) then
        raise exception 'not a member';
    end if;
    select coalesce(p.display_name, 'Scholar') into v_name
        from public.profiles p where p.id = auth.uid();
    insert into public.class_decks (class_id, shared_by, shared_by_name, name, card_count)
        values (p_class_id, auth.uid(), v_name, left(trim(p_name), 80),
                coalesce(jsonb_array_length(p_cards), 0))
        returning id into v_deck_id;
    insert into public.class_cards (class_deck_id, front, back, tags)
        select v_deck_id,
               left(coalesce(elem->>'front', ''), 2000),
               left(coalesce(elem->>'back', ''), 2000),
               coalesce((select array_agg(t) from jsonb_array_elements_text(elem->'tags') t), '{}')
        from jsonb_array_elements(p_cards) elem;
    return v_deck_id;
end; $$;

-- 7) Shared decks in a class I belong to.
create or replace function public.get_class_decks(p_class_id uuid)
returns table (id uuid, name text, shared_by_name text, card_count int)
language sql security definer set search_path = public as $$
    select d.id, d.name, d.shared_by_name, d.card_count
    from public.class_decks d
    where d.class_id = p_class_id
      and exists (select 1 from public.class_members me
                  where me.class_id = p_class_id and me.user_id = auth.uid())
    order by d.created_at desc;
$$;

-- 8) Cards of a shared deck (for preview / copying into my own collection).
create or replace function public.get_class_deck_cards(p_class_deck_id uuid)
returns table (front text, back text, tags text[])
language sql security definer set search_path = public as $$
    select c.front, c.back, c.tags
    from public.class_cards c
    join public.class_decks d on d.id = c.class_deck_id
    where c.class_deck_id = p_class_deck_id
      and exists (select 1 from public.class_members me
                  where me.class_id = d.class_id and me.user_id = auth.uid());
$$;

-- Lock execute to signed-in users only.
revoke execute on function
    public.create_class(text), public.join_class(text), public.get_my_classes(),
    public.get_class_roster(uuid), public.leave_class(uuid),
    public.share_deck_to_class(uuid, text, jsonb), public.get_class_decks(uuid),
    public.get_class_deck_cards(uuid)
    from public, anon;
grant execute on function
    public.create_class(text), public.join_class(text), public.get_my_classes(),
    public.get_class_roster(uuid), public.leave_class(uuid),
    public.share_deck_to_class(uuid, text, jsonb), public.get_class_decks(uuid),
    public.get_class_deck_cards(uuid)
    to authenticated;
