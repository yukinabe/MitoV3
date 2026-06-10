#!/usr/bin/env bash
# Deploy the mito-ai edge function + its secret.
#
# The DeepSeek key is NEVER stored in the repo — pass it in the environment when
# you run this. Run from the repo root (~/Desktop/mitoV3):
#
#   supabase login                       # one-time, opens a browser
#   DEEPSEEK_API_KEY=sk-... ./supabase/deploy-mito-ai.sh
#
set -euo pipefail

PROJECT_REF="ncnkvgpulnalauzxvfoh"

if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
  echo "ERROR: set DEEPSEEK_API_KEY in the environment before running." >&2
  echo "  DEEPSEEK_API_KEY=sk-... ./supabase/deploy-mito-ai.sh" >&2
  exit 1
fi

echo "→ Linking project $PROJECT_REF…"
supabase link --project-ref "$PROJECT_REF"

echo "→ Setting secrets (key is taken from the environment, not stored)…"
supabase secrets set DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY"
supabase secrets set DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-chat}"

echo "→ Deploying mito-ai…"
supabase functions deploy mito-ai

echo "✓ Done. Remember to also run the SQL migrations in supabase/migrations/ (SQL Editor)."
echo "  Then ROTATE the DeepSeek key you shared in chat and re-run this with the new one."
