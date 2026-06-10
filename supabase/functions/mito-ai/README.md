# mito-ai edge function

Backs the multiple-choice + type-in answer modes. Holds the DeepSeek key
server-side and exposes two tasks (`distractors`, `grade`) to the app.

## One-time setup (you must run these — they need your DeepSeek key + Supabase login)

```bash
# from the repo root (~/Desktop/mitoV3)

# 1. Apply the schema migrations in the SQL Editor (paste each file → Run):
#      supabase/migrations/0007_card_choices.sql   (multiple-choice cache)
#      supabase/migrations/0008_friends.sql        (friends)
#      supabase/migrations/0009_lobbies.sql        (lobbies / co-op / PvP)

# 2. Link the CLI to the project (once).
supabase link --project-ref ncnkvgpulnalauzxvfoh

# 3. Store the secrets.
supabase secrets set DEEPSEEK_API_KEY=sk-...           # your DeepSeek API key
supabase secrets set DEEPSEEK_MODEL=deepseek-chat      # optional; set the exact "v4" id when confirmed

# 4. Deploy.
supabase functions deploy mito-ai
```

## Local test (optional)

```bash
supabase functions serve mito-ai --env-file supabase/.env.local   # DEEPSEEK_API_KEY=... inside

curl -i -X POST http://localhost:54321/functions/v1/mito-ai \
  -H "Authorization: Bearer <a-supabase-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"task":"distractors","front":"What molecule stores cellular energy?","back":"ATP","deckName":"Biology","count":3}'
```

## In-app verification

A DEBUG self-test (`MitoBackend.runAISelfTest()`) exercises both tasks end to
end against the deployed function. Wire it to a debug button or a `-uitestAI`
launch arg the same way `runCloudSelfTest` is triggered.

## Notes
- The function is deployed **with** JWT verification, so only signed-in app users
  can call it — this is also where a premium/paywall entitlement check would go
  later (and where PvP grading would be made authoritative).
- `response_format: json_object` keeps DeepSeek's replies strictly parseable.
