# Character Movesets

First combat iteration: no damage classes, no weaknesses, no resistances, and no type matchups. Characters use simple RPG roles plus biology-themed visuals.

| Character | Role | Stats | Basic Attack | Skill | Ultimate | Theme / Animation |
| --- | --- | --- | --- | --- | --- | --- |
| Mito | Support | HP 48 / ATK 18 / DEF 14 | ATP Tap: free ATP spark, 18 damage | Cristae Surge: ATP team recharge and small energy shield, 20 damage | Powerhouse Burst: team sustain burst, 34 damage, 4 charge | ATP support / shield; spark, mito-cristae-surge, mito-powerhouse-burst |
| Chloro | DPS | HP 42 / ATK 22 / DEF 11 | Photon Shot: clean light hit, 22 damage | Sugar Rush: stored photosynthesis burst, 34 damage | Photosynthesis Bloom: big light finisher, 52 damage, 4 charge | Light / photosynthesis; beam, cloro-sugar-rush, cloro-photosynthesis-bloom |
| Astro | Support | HP 36 / ATK 24 / DEF 9 | Calcium Ping: small support signal, 16 damage | Synapse Buffer: glial support pulse, 24 damage | Glial Network: neural network burst, 40 damage, 4 charge | Neural support / network; pulse, astro-synapse-buffer, astro-glial-network |
| Dendri | Support | HP 38 / ATK 16 / DEF 12 | Scout Prick: immune scout jab, 16 damage | Present Antigen: mark-flavored support strike, 26 damage | Immune Rally: focused immune call, 42 damage, 4 charge | Immune scouting / antigen; jab, dendri-present-antigen, dendri-immune-rally |
| Neuro | Tank | HP 56 / ATK 14 / DEF 22 | Axon Zap: free electrical signal, 18 damage | Myelin Guard: shield-flavored pressure, 24 damage | Synaptic Overload: heavy signal finisher, 44 damage, 4 charge | Electric / signal; zap, neuro-myelin-guard, neuro-synaptic-overload |
| B Cell | Support | HP 34 / ATK 17 / DEF 10 | Antibody Tap: antibody projectile, 15 damage | Affinity Shield: defensive immune pressure, 22 damage | Memory Response: remembered immune surge, 38 damage, 4 charge | Immune / antibody; projectile, bcell-affinity-shield, bcell-memory-response |

## Implementation Notes

- Role labels are only `DPS`, `Tank`, and `Support`.
- Ability kinds are only `Basic`, `Skill`, and `Ultimate`.
- `theme` and `animationKey` are visual metadata only. They do not change damage calculations.
- Damage is determined by the chosen ability and team-level scaling, not by a damage class.
- Skill and ultimate animation sheets live in `MitoV3/Assets.xcassets/*.imageset` as 8-frame transparent strips with 200x128 logical frames.
- Future systems can add energy costs, animation playback, shields, heals, marks, buffs, or automatic Endless ability selection without adding type matchups.
