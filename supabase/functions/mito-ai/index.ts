// Mito V3 — AI edge function (DeepSeek)
//
// One authenticated endpoint, dispatched by `task`:
//   • "distractors" → plausible-but-wrong multiple-choice options for a card
//   • "grade"       → grade a typed answer on the FSRS 1..4 scale
//
// SECURITY MODEL
//   • The DeepSeek key NEVER ships in the app — it lives here as a Supabase
//     secret (DEEPSEEK_API_KEY) and is read only inside this function.
//   • Every request is authenticated with the caller's Supabase JWT (deployed
//     WITHOUT --no-verify-jwt).
//   • The caller may ONLY reference a card by `cardId`. The function looks the
//     card's text up from the database *as that user* (RLS-scoped), so the
//     prompt content is never attacker-controlled — you can't feed it arbitrary
//     text to use it as a general-purpose AI. The only free input is the typed
//     answer being graded.
//   • Output is forced to small, strict JSON (json_object + max_tokens), so the
//     model can't be coerced into returning long arbitrary completions.
//
// Deploy:
//   supabase secrets set DEEPSEEK_API_KEY=sk-...        # the DeepSeek key
//   supabase secrets set DEEPSEEK_MODEL=deepseek-chat   # optional; confirm "v4" id
//   supabase functions deploy mito-ai

import { createClient } from "jsr:@supabase/supabase-js@2";

const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const MODEL = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
const API_KEY = Deno.env.get("DEEPSEEK_API_KEY") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

interface AIRequest {
  task: "distractors" | "grade";
  cardId: string;
  count?: number | null;
  // Only meaningful for "grade": the learner's own typed input + behaviour.
  userAnswer?: string | null;
  elapsedMs?: number | null;
  signals?: {
    elapsedMs: number;
    timeToFirstKeystrokeMs: number;
    deletions: number;
    keystrokes: number;
  } | null;
}

interface CardText {
  front: string;
  back: string;
  deckName: string;
}

// Call DeepSeek in strict-JSON mode and parse the assistant message as JSON.
// max_tokens is deliberately small so the endpoint can't be abused to generate
// long arbitrary text.
async function deepseek(system: string, user: string, maxTokens: number): Promise<any> {
  const res = await fetch(DEEPSEEK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      temperature: 0.7,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
      stream: false,
    }),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`DeepSeek ${res.status}: ${detail}`);
  }
  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content ?? "{}";
  return JSON.parse(content);
}

// Look the card up AS THE CALLER (RLS applies), so we only ever feed the model
// real card content the user is already allowed to see — never client-supplied
// strings. Returns null if the card doesn't exist / isn't visible to them.
async function loadCard(authHeader: string, cardId: string): Promise<CardText | null> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data, error } = await supabase
    .from("cards")
    .select("front, back, decks(name)")
    .eq("id", cardId)
    .single();
  if (error || !data) return null;
  const deckName = Array.isArray((data as any).decks)
    ? (data as any).decks[0]?.name ?? ""
    : (data as any).decks?.name ?? "";
  return { front: String((data as any).front), back: String((data as any).back), deckName };
}

async function handleDistractors(card: CardText, count: number): Promise<Response> {
  const system =
    "You write multiple-choice distractors for study flashcards. Given a " +
    "question and its correct answer, produce plausible but DEFINITELY WRONG " +
    "options of the same type/category and similar length. Never include the " +
    "correct answer or paraphrases of it. No explanations. Respond ONLY as " +
    'JSON: {"distractors": ["...", "..."]}.';
  const user = JSON.stringify({
    deck: card.deckName,
    question: card.front,
    correctAnswer: card.back,
    howMany: count,
  });
  const out = await deepseek(system, user, 256);
  const distractors = Array.isArray(out?.distractors)
    ? out.distractors.map((d: unknown) => String(d)).slice(0, count)
    : [];
  return json({ distractors });
}

async function handleGrade(card: CardText, req: AIRequest): Promise<Response> {
  const system =
    "You grade a learner's typed flashcard answer for a spaced-repetition app " +
    "using the FSRS 1-4 scale: 1=Again (wrong/blank), 2=Hard (partially right " +
    "or correct but very slow/hesitant), 3=Good (correct), 4=Easy (correct, " +
    "confident, and fast). Judge SEMANTIC correctness first — accept synonyms, " +
    "minor typos, and different phrasing of the same concept. Use response time " +
    "and hesitation only as a secondary tie-breaker between adjacent grades. " +
    'Respond ONLY as JSON: {"rating": 1-4, "confidence": 0.0-1.0, "feedback": ' +
    '"one short sentence for the learner"}.';
  const learnerAnswer = String(req.userAnswer ?? "").slice(0, 600); // bound the only free input
  const user = JSON.stringify({
    question: card.front,
    correctAnswer: card.back,
    learnerAnswer,
    responseTimeMs: req.elapsedMs ?? req.signals?.elapsedMs ?? null,
    hesitation: req.signals
      ? {
          timeToFirstKeystrokeMs: req.signals.timeToFirstKeystrokeMs,
          deletions: req.signals.deletions,
          keystrokes: req.signals.keystrokes,
        }
      : null,
  });
  const out = await deepseek(system, user, 200);
  let rating = Number(out?.rating);
  if (!Number.isFinite(rating)) rating = 3;
  rating = Math.max(1, Math.min(4, Math.round(rating)));
  const confidence = Number.isFinite(Number(out?.confidence)) ? Number(out.confidence) : 0;
  const feedback = typeof out?.feedback === "string" ? out.feedback.slice(0, 240) : null;
  return json({ rating, confidence, feedback });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "POST only" }, 405);
  if (!API_KEY) return json({ error: "DEEPSEEK_API_KEY not configured" }, 500);

  const authHeader = request.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "missing authorization" }, 401);

  let req: AIRequest;
  try {
    req = await request.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!req.cardId) return json({ error: "cardId required" }, 400);

  try {
    const card = await loadCard(authHeader, req.cardId);
    if (!card) return json({ error: "card not found" }, 403);

    switch (req.task) {
      case "distractors": {
        const count = Math.max(1, Math.min(6, req.count ?? 3));
        return await handleDistractors(card, count);
      }
      case "grade":
        return await handleGrade(card, req);
      default:
        return json({ error: `unknown task: ${req.task}` }, 400);
    }
  } catch (err) {
    return json({ error: String(err) }, 502);
  }
});
