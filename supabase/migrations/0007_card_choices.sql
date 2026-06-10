-- Mito V3 — cached multiple-choice distractors
--
-- Multiple-choice answer mode shows the real answer (`cards.back`) alongside a
-- few plausible-but-wrong options. Those distractors are AI-generated once (via
-- the `mito-ai` edge function) and cached here so battle reads them with zero
-- latency and works offline. Stores ONLY the wrong answers — the correct one is
-- always `back`. Empty array = none generated yet (UI falls back to sibling
-- cards' answers until a backfill fills this in).
--
-- HOW TO APPLY: Supabase Dashboard → SQL Editor → paste this whole file → Run.

alter table public.cards
    add column if not exists choices jsonb not null default '[]'::jsonb;
