-- Mito — verify all 13 migrations are applied in a project.
--
-- These migrations were applied by hand in the SQL Editor (not via the CLI's
-- migration tracker), so the reliable check is "does each migration's signature
-- object exist?". Paste this whole file into Supabase → SQL Editor → Run.
--
-- Read the `applied` column: every row TRUE = all good. Any row FALSE = open
-- that numbered file in supabase/migrations/ and run it (all are idempotent, so
-- re-running an already-applied one is a harmless no-op).

select migration, applied from (values
  ('0001 card_states',
     to_regclass('public.card_states') is not null),
  ('0002 character_progress',
     to_regclass('public.character_progress') is not null),
  ('0003 cp fn search_path pinned',
     exists (select 1 from pg_proc
             where proname = 'touch_character_progress_updated_at' and proconfig is not null)),
  ('0004 wallet cols + events',
     exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='profiles' and column_name='atp')
     and to_regclass('public.events') is not null),
  ('0005 waitlist',
     to_regclass('public.waitlist') is not null),
  ('0006 fk indexes',
     exists (select 1 from pg_indexes where schemaname='public' and indexname='decks_owner_idx')),
  ('0007 cards.choices',
     exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='cards' and column_name='choices')),
  ('0008 friends',
     to_regclass('public.friendships') is not null
     and to_regprocedure('public.get_friends()') is not null),
  ('0009 lobbies',
     to_regclass('public.lobbies') is not null
     and to_regclass('public.lobby_members') is not null),
  ('0010 profiles RLS insert',
     exists (select 1 from pg_policies
             where schemaname='public' and tablename='profiles' and cmd='INSERT')),
  ('0011 delete_account()',
     to_regprocedure('public.delete_account()') is not null),
  ('0012 get_friend_league()',
     to_regprocedure('public.get_friend_league()') is not null),
  ('0013 classes',
     to_regclass('public.classes') is not null
     and to_regprocedure('public.create_class(text)') is not null)
) as t(migration, applied)
order by migration;
