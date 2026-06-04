-- Lock the trigger function search path for Supabase security advisor.

alter function public.touch_character_progress_updated_at()
    set search_path = '';
