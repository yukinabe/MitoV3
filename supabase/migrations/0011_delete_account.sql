-- Mito V3 — in-app account deletion (App Store Guideline 5.1.1(v))
--
-- Apple requires that any app offering account creation also lets the user
-- delete the account from inside the app. The client cannot delete its own
-- auth.users row with the publishable key, so this exposes a security-definer
-- RPC that deletes exactly the calling user. All app tables that reference
-- auth.users with ON DELETE CASCADE are wiped with it.
--
-- BEFORE SHIPPING, verify in Dashboard → Database that every user-keyed table
-- (profiles, decks, cards, card_states, character_progress, study_sessions,
-- events, wallets, waitlist, friendships, lobbies, lobby_members) has its FK
-- to auth.users set to ON DELETE CASCADE — any that don't will leave orphaned
-- rows after deletion.
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Additive / idempotent.

create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;
    delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
