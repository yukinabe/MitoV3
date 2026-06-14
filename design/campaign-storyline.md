# Mito — Campaign Storyline (design doc)

Status: **stages 1–3 written & implemented** (in `Tutorial.swift` → `CampaignStoryScript`). Stages 4–12 below are an outline to iterate on, not yet scripted.

## Premise — "The Fading"

Across the cell-world, the things a mind lets slip don't just vanish — they **rot**. Forgotten knowledge curdles into Mutagems, and worse, it corrupts the body's own guardians: organelles and cells twisted feral by everything their host has forgotten.

**Mito** is immune, because Mito turns focus into power (ATP) — it *is* memory made physical. So it falls to Mito and the player to push the Fading back the only way that works: by **remembering**. Every card recalled restores a little of what was lost.

The hook that makes the game's core mechanic make sense:
- **Bosses aren't killed — they're cured.** Each campaign boss is a guardian the Fading twisted. You out-remember them until they snap back to themselves, and then they join you. Studying = restoring.
- **Studying earns ATP** = literally powering your restored team back up.

The slow reveal: the Fading has a source — the **Spikevyrus** (already the stage-12 boss). It wasn't always a plague; it was the *first* guardian to fall, and its forgetting is contagious.

## Tone & voice

Cozy-but-witty, never grimdark. The stakes are real (memory, decay) but the script stays light and character-driven.
- **Mito** — warm, wry, a little self-deprecating ("your brain's the weapon. kinda poetic"). The steady center.
- **Chloro** — cocky DPS, allergic to sincerity, deflects with jokes ("i had the weirdest dream where i was a feral lamp").
- **Neuro** — terse, dutiful tank ("i hold the line. nothing gets past me twice"). Straight-man to Chloro.
- **Astro** — spacey, gentle, talks in metaphors/signals.
- **Dendri** — eager scout, over-shares, finds clues.
- **B Cell** — careful, remembers everything (immune memory), the lorekeeper.

## Structure

12 stages on the existing map. Six are **recruit** stages (cure → join). The rest are **story/mechanic** beats that pace the arc and escalate toward the Spikevyrus. Each stage gets an **intro** (plays as combat opens, boss visible) and an **outro** (plays on win, before the recruit/capture popup).

| Stage | Region | Type | Beat |
|------|--------|------|------|
| 1 | Petri Plain | Recruit → **Chloro** | ✅ Mito finds a dimmed chloroplast; restores the light. |
| 2 | Membrane Marsh | Story (capture) | ✅ A Spikevyrus *scout* — first proof the Fading is *spread*, not random. Teaches capture. |
| 3 | Nucleus Hollow | Recruit → **Neuro** | ✅ A neuron with scrambled signals; straighten its wires. Chloro/Neuro friction begins. |
| 4 | Mitochondria Cave | Recruit → **Astro** | An astrocyte lost in its own network; Mito (home turf) coaxes it back. Astro "hears" the Fading's hum — first hint of a single source. |
| 5 | Ribosome Ridge | Recruit → **Dendri** | A dendritic scout, hyper-alert and paranoid from watching the spread. Joins; brings the first hard clue (a "patient zero" trail). |
| 6 | Golgi Gorge | Recruit → **B Cell** | The lorekeeper. Once restored, B Cell *remembers* what the others forgot: the Fading started with one guardian. Team now complete (6). |
| 7 | Lysosome Lair | Story (capture: Cytocrawler) | Following the trail into the body's "recycling." Confront how much has already been lost. Mood darkens a notch. |
| 8 | Vacuole Vale | **Mini-boss** | A bloated, Fading-saturated lieutenant (corrupted Spikevyrus spawn). First real wall — proves the source is close and strong. |
| 9 | Cytoskel Span | Story | The team crosses the scaffolding toward the core. Character check-ins; Chloro/Neuro have grown on each other. Quiet-before-the-storm. |
| 10 | Plastid Pass | Story (setback) | A cost beat: the Fading takes something/someone back, or a member nearly relapses. Raises the stakes before the finale. |
| 11 | Vesicle Vault | Story (prep) | Gather strength; B Cell explains *how* to cure the source (you can't just beat it — you have to make it remember what it was). |
| 12 | Spike Citadel | **Final boss → Spikevyrus** | The origin. Reveal: it was the first guardian, and it's been trying to forget something unbearable. The "fight" is forcing it to remember. Resolution: cured/captured, the Fading recedes. Sets up post-game (endless = keeping the Fading at bay). |

## Open questions / iteration hooks

- **Stage names vs. recruits**: current map names (e.g., "Mitochondria Cave" at the Astro stage) don't always match the hero thematically. Optional polish: rename stages to fit their boss, or re-order recruits to fit the names.
- **Final boss**: cure Spikevyrus (add to roster, mirrors the theme) vs. defeat-and-seal. Curing is more on-theme and reuses the capture/recruit flow.
- **Replayability**: once a stage is cured, it reverts to a generic Spikevyrus fight (already implemented) for farming — story plays once.
- **Length**: stages 7–11 are currently "story" placeholders; some could become recruit stages if more characters get built, or capture stages for the wild creatures (Mutagem/Cytocrawler).

## Implementation notes

- Scripts live in `MitoV3/Tutorial.swift` → `CampaignStoryScript.intro(stage:)` / `.outro(stage:)`. Add `case N:` blocks to script more stages — no other wiring needed; `BattleView` already plays intro on combat open and outro on win for every campaign stage.
- Recruit mapping: `CampaignRecruits.byStage` in `GameData.swift`.
- Dialogue beats use `TutorialBeat.say(speaker:name:text:partner:partnerName:)` — `speaker` is bottom-right (large), `partner` bottom-left (mirrored). Sprites: `hero-*-hop`, `wild-*-hop`.
