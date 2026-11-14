# DeepSting — Game Design Document (living)

> Status: **Milestone 4 complete** (the full descent: chapters 1–4 with alternate floors, first ending). This is the source of truth for design. When code and this document disagree, fix one of them in the same commit.
> Every ambiguity resolved during development goes in **§19 Decisions Log**. Questions that would be expensive to change later go in **§20 Open Questions**.

---

## 0. Title, pitch, pillars

### Working title: **DeepSting**

**Alternative titles**
1. **Undercomb**: short and ownable. It says "hive" and "underground" in one word.
2. **Sludgehive**: tells you the tone straight away (gross and charming). It's easy to search for.
3. **Stinger Below**: clearest about the genre (you shoot, you go down), but the least distinctive of the three.

**Elevator pitch**
> *The world's most polluted basin is the last place left to build. You're a yellowjacket digging the colony down through rotting comb, buried landfill, crystal caverns and drowned ruins, toward the toxic heart of the basin. Shoot venom, dig through walls for secrets, rescue lost brood, and watch your worker swarm haul treasure home after every room. Every relic you dig up changes your stinger. Every win unlocks something deeper.*

**Title (locked, Q6):** **DeepSting**. **Tagline:** *Stung too deep.*

### Design pillars
1. **Every run teaches you something.** New items, rooms and brood unlock almost every run early on. Progression is horizontal (more content and options), never a stat treadmill.
2. **Your stinger is your build.** Item modifiers stack generically and *visibly*. A player can read their build from the projectile alone.
3. **Readable chaos.** Every attack is telegraphed. Bullets have a strict color and shape language. Hand-authored rooms make for fair fights.
4. **Dig to discover.** Digging is how you get the secrets, and the clues to them are deducible from the map and the walls.
5. **The colony is the reward.** Workers hauling loot and rescued brood filling the hive make your progress visible and warm.

---

## 1. Design references (what we take, structurally)

We borrow structures only. No names, art, text or specific items from any existing game.

| Source | Structure we use | Where it lands |
|---|---|---|
| Binding of Isaac (series) | 2 floors per chapter, a boss on every floor, chapters unlocked by winning, grid floor generation, special rooms on dead ends, deducible secret rooms, bombs/keys/coins as decisions, devil/angel deals, curses, ~40% of items locked at launch, completion marks, alternate characters, an alternate path behind hidden exits | §6, §10, §11, §13 |
| Enter the Gungeon | Collection book with flavor text, synergy callouts in UI, NPC rescues that unlock hub features | §13 Trove, §12 |
| Dead Cells | Meta-currency lost on death if not yet banked | §5 |
| Hades | Hub that visibly changes, choose 1 of 3 rewards, opt-in Heat-style difficulty | §13, §14 |
| Nuclear Throne | Radiation meter → choose 1 of 3 mutations | §10.4 |
| Risk of Rain 2 | Readable stacking and color-coded rarity | §7 |
| Slay the Spire | Ascension-style incremental difficulty | §13 Contamination |
| Spelunky 2 | Multi-step secret routes shared as community knowledge | §10.5 alternate path |
| Vampire Survivors | Very frequent early unlocks, evolutions from item pairs | §13 cadence |
| Rogue Legacy (counter-example) | Heavy permanent stat inflation makes skill feel irrelevant, so we cap it | §13 Hive Upgrades |

---

## 2. Premise, world, tone

The colony lives on the rim of **the Basin**, the most polluted place in the world. Factory runoff pipes drain into it, radioactive waste seeps through the soil, and decades of trash are buried in layers. There is nowhere left to build on the surface, so the wasp digs **down**.

- **Tone:** darkly whimsical, gross but charming. The world is grim, but the wasp is plucky, the brood are adorable, and the mutants are more pitiful than evil.
- **Visual pollution language** (on every floor, more of it with depth): rusted drums, sludge seams in the walls, glowing puddles, trash layered into the strata, pipe mouths dripping. By chapter 5 the soil itself glows.
- **Narrative delivery:** no cutscenes. Story comes through item field notes, brood dialogue in the hive, boss intro cards and short ending vignettes (Isaac-style ending slides).
- **The secret story:** the alternate path reveals that the *Reactor Vault* at the bottom is still running and keeps producing the mutants. The true ending is shutting it off.

---

## 3. The player

### 3.1 Controls (defaults, all rebindable)

| Action | Keyboard + mouse | Keyboard only | Gamepad |
|---|---|---|---|
| Move | WASD | WASD | Left stick / D-pad |
| Shoot | Arrow keys (or LMB toward cursor, free aim) | Arrow keys | Right stick (360°) or face buttons (4-dir) |
| Dash | Shift / RMB | Shift | RB / R1 |
| Use active item | Space | Space | RT / R2 |
| Place Dig Charge | E | E | LB / L1 |
| Use Fossil / Fluid | Q | Q | LT / L2 |
| Swap Fossil/Fluid slot | Ctrl | Ctrl | Select / Back |
| Map (hold) | Tab | Tab | D-pad press (hold) |
| Pause | Esc | Esc | Start |
| Debug console (dev builds only) | ` | ` | — |

**Aim mode setting:** `4-dir` (Isaac default for keyboard) / `8-dir` / `free` (default for mouse and right stick). In free aim a shot keeps a small (15%) amount of the player's velocity, like Isaac's tear inertia. 4-dir snaps to the nearest cardinal.

### 3.2 Movement
- **Low hover with momentum:** acceleration `1800 px/s²`, friction `1400 px/s²`, base speed `150 px/s` (= Move Speed 1.0). Tuned at 640×360 logical resolution.
- **Dash:** 0.14 s burst at 3× speed with i-frames for its whole duration, then 0.9 s cooldown. Dashing through enemy bullets doesn't destroy them. The dash cancels sludge slow for its duration.
- **Hover rules:** the wasp ignores ground spikes, floor hazards marked `ground`, and creep pools marked `ground` (except sludge, which "sticks to wings" and still slows). Webs, falling rubble, toxic gas, sludge, pits and rocks still apply.
- **True flight** (from items): also ignores pits and rocks, and lets the wasp hover over obstacles. It renders with a taller shadow offset.

### 3.3 Stats (Isaac knobs)

| Stat | Base | Floor | Cap | Notes |
|---|---|---|---|---|
| Health (container slots) | 3 cells | 1 | 12 cells | 1 cell = 2 half-points |
| Damage | 3.5 | 0.5 | — | multipliers applied after flat bonuses |
| Fire Rate (shots/s) | 2.7 | 0.5 | 30 | expressed as shots/sec internally (not "tear delay") |
| Shot Speed | 1.0 | 0.6 | 2.5 | × 190 px/s |
| Range (px) | 150 | 40 | 600 | travel distance before the shot drops |
| Move Speed | 1.0 | 0.4 | 2.0 | × 95 px/s |
| Luck | 0 | -5 | 10 | feeds proc chances: `chance = base + luck * per_luck` |

**Stat formula:** `final = clamp((base + Σflat) × Π(mult), floor, cap)`. Damage also takes a per-caste multiplier. Stats recalculate whenever the inventory changes (an event, not every frame).

### 3.4 Health
*(User decision: health stays as hearts.)*
- **Hearts** (red hearts): containers that can be refilled with heart pickups.
- **Chitin** (soul hearts): temporary shield halves layered after the hearts. Lost first. Not refillable once gone.
- **Toxic Spined Chitin** (black hearts): like Chitin, but each half that breaks deals 20 damage to every enemy in the room.
- **Damage order:** shields (last gained first) → hearts.
- **Max total cells (all types):** 12. Pickups past the cap are wasted, as in Isaac.
- **Hits:** most enemy damage is a half cell, and from chapter 4 on it is a full cell. Damage taken grants 1.0 s of i-frames with a blinking sprite.

---

## 4. Consumables (Isaac mapping)

| Isaac | DeepSting | Cap | Rules |
|---|---|---|---|
| Coins | **Mana** (crystalline chits) | 99 | in-run currency, dropped as crystal flakes: **Chip** = 1 (penny), **Fragment** = 5 (nickel), **Chunk** = 10 (dime), **Crystal** = 25 (quarter). Shops, Arcades, Vault donation |
| Bombs | **Dig Charges** | 99 | 0.9 s fuse; 60 px radius; 60 dmg; destroys rocks, tinted rocks, cracked walls (secret entrances), poop-equivalent "trash heaps"; hurts the player (1 cell) |
| Keys | **Royal Jelly** *(for now, user decision)* | 99 | open locked doors (Dig Site from ch2+, Library, Vault ×2), sealed caches, key-blocks |
| Pills | **Strange Fluids** | 1 slot (2 with item) | 20 effects, randomly mapped per run to 13 vial colors; identified after first use (Alchemist brood: identified on sight) |
| Cards/Runes | **Fossils** | shared slot with fluids | 20 single-use powers, always identified |

**Secret wall readability:** a cracked wall shows hairline fractures plus a *faint* dust trickle every few seconds, and sometimes a root poking through. The tutorial room on floor 1 shows an obvious one. Later floors make the cracks subtler, but the dust tell never goes away. A curse can hide the dust.

---

## 5. Resources, workers and banking (signature mechanic)

### 5.1 Deposits
When a room is cleared it spawns **resource deposits** (1–4 nodes, from the room template's `deposit_slots` plus RNG). The deposit type depends on the stratum:

| Resource | Where | Primary meta use |
|---|---|---|
| Wood Pulp | Hive, Topsoil | hive cosmetics, cheap Comb Upgrades |
| Nectar | Topsoil, Flooded Burrows | Larder boons |
| Amber | Bedrock, Ruins | mid-tier Comb Upgrades |
| Protein | everywhere (enemy remains) | brood upkeep flavor + roster unlocks |
| Minerals | Landfill, Bedrock, Mine, Runoff | high-tier Comb Upgrades |
| Relic Shards (rare) | Ruins, Catacombs, Basin, alt path | prestige upgrades and cosmetics |

**One banked currency: Pulp** (user decision, Q4). Every banked material goes through **the Pulper** in the hive and becomes Pulp at its `pulp_value` (`/data/resources/*.json`: wood pulp, nectar and protein are 1, amber and minerals are 2, relic shards are 5). Lifetime per-type totals are still recorded, and they decide which hive decorations grow.

### 5.2 The worker swarm
1. Room clears → doors unlock → deposits pop out of the ground (0.3 s).
2. **Workers** (4–10, scaled to deposit value) fly in through the door that leads toward the **nest entrance**, which is the next step along the shortest path back to the start room. They swarm the deposits, harvest for about 1.5 s, then fly back out the same door.
3. Hauling completes when the last worker leaves (about 2–3 s). If the player leaves mid-haul, the swarm finishes off-screen and the haul is credited at once. A toast shows "+12 → floor stash".
4. Workers are **untargetable and invulnerable**, and enemies ignore them. They never appear in rooms that aren't cleared. They only exist for the visual and for timing.
5. **Floor stash (user decision, Q3):** hauls go into the **floor stash** (HUD: "Stash N"), not the bank. **Dying loses the whole unbanked stash.**
6. **The way up:** killing the floor boss opens a **light shaft to the surface** in the boss room. The stash (plus the boss carcass as Protein) piles up under it, and a big worker swarm streams down the shaft and carries it all up, which you can watch. When the last worker is out, the stash goes through the Pulper and is **banked as Pulp**, and only then does the trapdoor down appear. If you leave the boss room mid-haul, it completes immediately.
7. **Mana is separate:** in-run Mana is only found as pickups (from room-clear rewards, enemies, rocks with the right item, secret rooms). It is never converted from hauls.

> Risk/reward lever: everything you've hauled on this floor is at risk until you beat the boss. A greedy, careful clear is worth a lot, and a death right before the boss costs a lot.

### 5.3 Brood rescue is always banked immediately (§12).

---

## 6. Items

### 6.1 Categories
- **Passive**: permanent for the run, unlimited.
- **Active**: one slot (two with an item). Charges by room clears (`charge` 1–12 rooms) or by time.
- **Knick-knacks** (trinkets): one slot (two with an item), swappable by dropping. Can be "absorbed" with a Fluid effect.
- **Fossils**: single use (cards/runes).
- **Strange Fluids**: single use, unidentified at first (pills).

### 6.2 Quality tiers

| Q | Color | Meaning | Typical pool weight |
|---|---|---|---|
| 0 | grey | flavor, minor stat | 1.0 |
| 1 | white | solid stat item | 1.0 |
| 2 | green | build-shaping | 0.8 |
| 3 | blue | strong / modifier | 0.5 |
| 4 | amber-gold | run-defining | 0.2 |

The quality color shows on the pedestal glow, the Trove entry and the pickup banner (with an icon *and* a color for colorblind safety).

### 6.3 Pools
Dig Site (treasure), Trader (shop), Boss, Secret, Royal (angel), Mutation (devil), Cursed, Vault (golden), Library (fossils + bookish relics), Arcade (prize), Brood Cell, Challenge, plus **Strata pools** (Hive, Topsoil, Landfill, Bedrock, Ruins, Runoff, Basin, Aquifer, Fault, Reactor). Strata pools fill 25% of Dig Site rolls on matching floors.

**Pool algorithm (Isaac-like):**
- Each pool entry is `{item_id, weight}`. Only unlocked items are eligible.
- When an item is *seen* (spawned on a pedestal) it is removed from **all** pools for the rest of the run. Rerolls also remove the item.
- If a pool is exhausted, roll from Dig Site. If that is empty too, spawn the fallback item `lint` (Q0, "Pocket Lint").
- Rolls use `RNG.stream("items")`, so the same seed gives the same items in the same order of rolls.

### 6.4 Effect system (architecture)
An item is data (`/data/items/<id>.json`) that lists **effects**. Each effect is a small `ItemEffect` script with a type key and params. The `EffectHost` on the player dispatches hooks:

```
stat_mod           {stat, add?, mult?}
projectile_mod     {modifier: "pierce"|"bounce"|"split"|"homing"|"element"|"size"|"orbit"|"boomerang"|"spectral"|..., params}
on_hit             {effect, chance, per_luck}
on_kill            {...}
on_room_clear      {...}
on_floor_start     {...}
on_damage_taken    {...}
familiar           {scene_id, params}
orbital            {scene_id, radius, speed}
active             {ability_id, charge, charge_type}
health             {heart_containers?, heal?, chitin?, toxic_chitin?}   (half-hearts, except containers)
pickup_spawn       {pickup, count}
flag               {name}   (e.g. "flight", "spectral", "see_secrets")
```
Adding an item = writing a JSON file. A new *kind* of behavior = one new effect script that registers its type key. Gameplay code never checks `if item == "x"`.

### 6.5 Composable stinger (projectile modifiers)
A shot is a `ShotSpec` assembled every time stats change:
- **Scalar fields:** damage, speed, range, size, knockback, color, trail, sprite_id.
- **Modifier list**, ordered by a fixed `priority` (not pickup order) so builds are deterministic:
  `size(0) → element(10) → spectral(20) → pierce(30) → homing(40) → bounce(50) → split(60) → orbit/boomerang(70) → on_hit procs(90)`.
- **Rules that make any combination work generically:**
  - *pierce* sets `pierce_count` (−1 = infinite). *bounce* sets `bounce_count` for walls. When a shot hits an enemy and has pierce left, it continues.
  - *split* spawns child shots on hit or expiry. Children inherit the **whole spec except split**, at a damage multiplier ≤ 0.5. Recursion depth is capped at 1 unless a Q4 item raises it.
  - *homing* steers by `turn_rate`. It stacks additively up to a cap.
  - *element* adds a status (poison, burn, slow, charm, freeze). Several elements coexist. The color blends toward the most recent element, and the trail shows all of them as a striped ribbon.
  - Mutually exclusive delivery types (beam, lobbed, orbit) resolve by the highest `priority` delivery, and the others convert into compatible modifiers (e.g. *orbit* + *beam* = rotating beam is **not** hand-coded: beam is just "a shot with infinite speed rendered as a line", so modifiers apply along it).
- **Visuals compose from the spec**: size scales the sprite, each element adds a tint and particle, pierce stretches the stinger, bounce adds a ricochet spark, split shows facets, homing adds a seeker glint. Any item can also add a `player_overlay` sprite (hat, glow, extra wings).
- The Trove and pickup banner say **"Synergy!"** when a new item's modifier changes an existing modifier's behavior (detected generically: two or more modifiers with `synergy_tag` overlap).

### 6.5b As built in Milestone 3
- **61 items, 15 knick-knacks, 10 fossils, 12 Strange Fluids, 12 mutations** (all data in `/data`).
- Effect types: `stat_mod`, `projectile_mod`, `proc`, `trigger`, `aura`, `familiar` (shooter / orbital / biter), `flag`, `health`, `consumables`, `active`, `ability`, `perma_stat`, `room_stat`, `radiation`.
- Projectile modifiers: size, multishot, element (poison / slow / burn / shock), spectral, pierce, homing, wave, bounce, split, boomerang, knockback. Each element adds a colored ring to the stinger, and boomerangs spin.
- The **Synergy Lab** (main menu → Synergy Lab in dev builds) is a firing range of training dummies that show damage numbers, with a toggle for every item / knick-knack / mutation and a live readout of the composed shot.

### 6.6 Starter item list (expanded seed list; target 120+ at launch)
*(Names are original. "fn" = archaeologist's field note.)*

**Gems and stones**
| id | Name | Q | Effect |
|---|---|---|---|
| raw_geode | Raw Geode | 3 | shots split into 3 on hit |
| obsidian_shard | Obsidian Shard | 2 | piercing shots |
| quartz_lens | Quartz Lens | 2 | +80 range, 15% (+3%/luck) homing shots |
| amber_gnat | Amber with a Gnat Inside | 2 | gnat familiar that bites |
| opal_fragment | Opal Fragment | 2 | random element per room |
| pyrite_tooth | Fool's Molar | 1 | +2 Mana per room clear |
| salt_crystal | Salt Lick | 1 | +0.3 shot speed, shots slow enemies |
| glow_pebble | Glowing Pebble | 1 | +1 luck, emits light (counters Cave-in) |

**Relics**
| id | Name | Q | Effect |
|---|---|---|---|
| scarab_amulet | Scarab Amulet | 4 | revive once with 1 cell |
| bronze_arrowhead | Bronze Arrowhead | 2 | +0.2 shot speed, 10% crits (×2) |
| clay_idol | Clay Idol | 2 | orbital that blocks bullets |
| cracked_crown | Cracked Crown | 4 | +all stats, take double damage |
| sun_disk | Sun Disk | 3 | active (4 rooms): charged beam |
| canopic_jar | Canopic Jar | 3 | on kill, 5% chance of a Chitin half |
| temple_bell | Temple Bell | 2 | active (3): stun every enemy for 2 s |

**Everyday buried objects**
| id | Name | Q | Effect |
|---|---|---|---|
| bottle_cap | Bottle Cap | 2 | shots bounce off walls twice |
| wedding_ring | Lost Wedding Ring | 2 | +1 luck, +1 Chitin at floor start |
| rusty_spoon | Rusty Spoon | 1 | shots leave short sludge puddles that hurt enemies |
| toy_soldier | Toy Soldier | 2 | familiar that shoots |
| dead_phone | Dead Phone | 1 | active (2): stun flash |
| marble | Marble | 1 | shots roll along the ground (low arc, ignore range drop) |
| coin_purse | Old Coin Purse | 1 | +50% Mana share |
| gnome_hat | Garden Gnome Hat | 2 | +1 heart, a tiny gnome hat on the wasp; rocks drop Mana chips (easter-egg nod to the developer's other game) |
| bent_fork | Bent Fork | 1 | +0.5 damage |
| sports_bottle | Squeeze Bottle | 1 | +0.4 fire rate |
| battery_9v | Swollen Battery | 2 | active items charge 1 extra per clear |
| bubble_wrap | Bubble Wrap | 1 | +2 Chitin halves |
| shoelace | Frayed Shoelace | 1 | +0.15 move speed |
| reading_glasses | Reading Glasses | 2 | shows secret-room hints on the map |
| tin_can_phone | Tin Can Telephone | 2 | shots boomerang |
| lighter | Dead Lighter | 2 | 10% burn shots |

**Fossils** (20 at launch): Trilobite (reveal map), Ammonite (spiral shot burst), Shark Tooth (room-long damage up), Coprolite (fertilizes: rocks become deposits), Belemnite (piercing volley), Crinoid Stem (spawn a Dig Charge per enemy killed this room), Ichnite (teleport to the boss room), Petrified Wood (gain 3 Dig Charges), …

**Strange Fluids** (20 at launch): stat up/down pairs, *Antifreeze* (freeze the room), *Mystery Runoff* (random teleport), *Glowing Slurry* (+radiation), *Tap Water?* (heal fully), *Re-identify* (reshuffles colors), …

---

## 7. Enemies (mutated critters)

### 7.1 Bullet and telegraph language (strict)
- **Player shots:** amber/gold, with a clear dark outline.
- **Enemy shots:** *red* for standard shots, *toxic green* for status or creep-leaving shots, *violet* for homing or special. Colorblind palettes swap these to shape-coded sets (circle / diamond / ring) plus high-contrast outlines (see §15).
- **Every attack telegraphs:** a wind-up pose of at least 0.35 s (0.5 s on floor 1), an audio cue, and a flash on the emitter. Bullet-pattern casters show a faint ghost of the pattern for 0.25 s first.
- **No offscreen spawns into the player.** Spawns always show a 0.6 s emergence animation.

### 7.2 Archetypes
| Archetype | Example critter | Behavior |
|---|---|---|
| Chaser | Twin-headed Grub | walks at the player; heads argue (random stutter) |
| Turret | Bloat Tick | stationary, telegraphs, fires 4-way or aimed |
| Burrower | Mole Cricket | submerges, surfaces under the player area, sprays a ring |
| Flyer | Glowmoth | erratic flight, ignores rocks, dives |
| Splitter | Sludge Worm | splits into 2 smaller worms on death (2 generations) |
| Caster | Lantern Centipede | segmented; fires patterned volleys from its segments |
| Swarmer | Feral Ant | spawns in groups of 5–8, weak, flanks |
| Mimic | Biting Cache | a sealed cache that bites when you open it; telegraphed by a breathing wobble |
| Charger | Rust Beetle | locks on, charges in a line, stuns itself on walls |
| Creep-layer | Drip Slug | leaves a toxic trail |

### 7.3 Champions (Isaac-style)
Any non-boss enemy can roll champion (base 5%, +luck has no effect, +5% per Contamination level, curses can raise it). A champion gets a tint plus one modifier: **Tough** (×2 HP), **Splitting**, **Toxic Trail**, **Fast**, **Volatile** (explodes on death, telegraphed), **Shielded** (blocks the first 3 hits), **Regenerating**, **Radiant** (+radiation on kill, drops extra Protein). Champions drop a guaranteed pickup.

### 7.4 Families per stratum (6–10 each at full launch; M1 builds the first 4)
- **Abandoned Hive:** Twin-headed Grub, Bloat Tick, Feral Ant, Comb Mite, Paper Moth, Waxworm.
- **Topsoil:** Mole Cricket, Root Grub, Drip Slug, Rust Beetle, Earwig Duelist.
- **Flooded Burrows:** Leech Coil, Drowned Ant, Bubble Tick, Mud Skipper.
- **Landfill:** Cap Crab (wears a bottle cap), Wrapper Moth, Tin Roach, Battery Slug.
- **Sewer Pipes:** Pipe Eel, Grease Fly, Sludge Worm (big), Clog.
- **Bedrock / Collapsed Mine:** Crystal Tick, Geode Shell, Lantern Centipede, Cart Beetle, Dust Wraith-moth.
- **Ruins / Catacombs:** Scarab Sentinel, Mummy Grub, Urn Spider, Bone Ant.
- **Runoff / Basin:** Drum Toad, Two-tailed Scorpion, Glowing Isopod, Ooze Mother.

### 7.5 Bosses (at least 3 per chapter pool)
| Ch | Boss pool |
|---|---|
| 1 | **The Broodless Mother** (hollow queen husk, spawns comb mites), **Grubking** (giant twin-head, splits), **Tunnel Mole** (burrower patterns) |
| 2 | **Heap** (living trash pile), **The Rat Hoarder** (fake shop mimic), **Sewer Mouth** |
| 3 | **Geode Golem**, **Crystal Mantis**, **Old Drill** (abandoned machine with a beetle inside) |
| 4 | **The Entombed Pharaoh-beetle**, **Urn Mother**, **Catacomb Choir** (3 synced skulls) → **first ending boss: The Gilded Idol** |
| 5 | **Drum Hydra**, **Outflow** (pipe mouth boss) |
| 6 | **The Basin Heart** (true final boss) |
| ★ | **The Hollow Swarm**: timed secret boss, reached if the player gets to ch3's end within 20:00 |
| ★ | **Reactor Core Warden** (alt-path final) · **The Old Queen** (Queen's Chamber super-boss) |

Each boss has 2–3 phases, a HUD health bar, a name card, and is fully pattern-telegraphed.

---

## 8. Floors and chapters

| Ch | Floor A | Floor B | Alt (for floor B, or both from ch2) |
|---|---|---|---|
| 1 | **The Abandoned Hive** (always floor 1) | **Topsoil** | Flooded Burrows (floor 2 only) |
| 2 | **Landfill Layer** | Landfill Layer | Sewer Pipes |
| 3 | **Bedrock Caverns** | Bedrock Caverns | Collapsed Mine |
| 4 | **Buried Ruins** | Buried Ruins | Catacombs → first ending |
| 5 | **Runoff Seam** | Runoff Seam | — (unlocked by first win) |
| 6 | **The Basin Floor** | — | — (true final) |
| ★ | Aquifer → Fault Line → Reactor Vault | | alt path via hidden exits |
| ★ | The Queen's Chamber | | post-game super-boss |

- **Alt-variant chance:** 0% until unlocked by an achievement, then 33% per floor (Isaac Afterbirth model). Achievements unlock each alt.
- **Gating (unlock-gated depth):** at first a run ends after the chapter 4 boss with ending 1. Wins unlock ch5, then ch6, then the alt-path exits (Oracle brood), then the Queen's Chamber.
- **Floor length:** Room count grows with depth (§11).

### 8.1 Curses (one at most per floor; 0% on floor 1 of the first 3 runs)
| Curse | Effect | Isaac analogue |
|---|---|---|
| **Cave-in** | darkness: small light radius around the wasp | Darkness |
| **Tremor** | the minimap only shows rooms you have visited (D31) | Lost |
| **Toxic Fog** | pedestal items show as "?" until picked up | Blind |
| **Labyrinth** | XL floor (×1.8 rooms, cap 30) with 2 Dig Sites; no floor skip yet (D31) | Labyrinth |
| **Silt** | room icons hidden on the map (special rooms are unknown) | Unknown-ish |
| **Spore Bloom** | (late-game unlock, `curse:spore_bloom`) enemies are 15% more likely to be champions; lands with champions in M4 | — |

Base curse chance 15% per floor (`curse_chance`), except floor 1 during the first 3 runs (`curse_free_runs`). It's adjusted by items and Contamination later. The curse is shown in the floor banner, under the HUD consumables and on the pause screen. Debug: `curse <id|none>` regenerates the floor.

### 8.2 Radiation and Mutations (second build axis)
- The **Radiation meter** fills from killing mutants (1 per kill, 5 per champion, 20 per boss), from standing in glowing contamination (+5/s) and from some Fluids.
- Threshold starts at 60, then +30 each time (60, 90, 120, …).
- When it's full: at the next room clear (never mid-fight) a choice of **1 of 3 Mutations** appears.
- Mutations are run-only, small and stackable, and have their own pool. Examples: *Extra Eye* (+range), *Thick Carapace* (+1 Chitin, −speed), *Glow Glands* (light radius, enemies take damage near you), *Spiracles* (dash cooldown −30%), *Twin Stinger* (an extra side shot at 30% damage), *Hungry Gut* (healing from Protein deposits), *Static Fuzz* (shots chain lightning 10%).
- Some Mutations are unlockable via achievements (included in the unlock count).

### 8.3 Special rooms
| Room | Placement | Contents |
|---|---|---|
| Start | center | tutorial art on floor 1 |
| Boss | farthest dead end | boss + trapdoor + reward pedestal |
| Dig Site (treasure) | dead end, always | 1 item from Dig Site (25% Strata pool when one exists); Royal Jelly lock from depth 3 |
| Trader (shop) | dead end, always | 2 Trader pool items (10–25 Mana by quality) + 3 consumables (heart 3, Dig Charge 5, Royal Jelly 5, Chitin 5); NPC **Mott**, a hoarding pack rat; Royal Jelly lock from floor 2 |
| Vault | dead end, ch2+ | 2 Royal Jelly to open; Vault pool item; option to donate Mana |
| Arcade | dead end, ch2+ | gamble Mana: slot beetle, fortune worm, crane game |
| Sacrifice Altar | dead end | step on the spikes: half a heart per use; each use on the floor rolls a better table (`config/sacrifice.json`) |
| Curse room | dead end | spiked door; cursed pool item / pickups |
| Library | dead end, rarer | fossils + Library pool items (requires Archivist unlock) |
| Challenge | dead end | door only opens at full hearts; 3 waves of the stratum's enemies, then the pedestal unlocks |
| Mini-boss | dead end | Matriarch Tick or Brute Grub; 2 guaranteed pickups |
| **Brood Cell** | dead end; rare outside floor 1 | sealed brood cells; may hold mutated brood |
| Secret | empty cell bordering ≥3 rooms | Secret pool / consumables |
| Super-secret | empty cell bordering exactly 1 room (not boss) | Royal/Mutation-lite item or big pickup cache |
| Royal Chamber / Mutation Den | reachable from the boss room post-fight | angel/devil equivalent (§8.4) |

### 8.4 Royal Chamber / Mutation Den (angel/devil)
- After the boss dies, a door may appear on a free wall of the boss room, leading to an off-map room. Chance (`config/floorgen.deal`): 0% on floor 1, otherwise 30% base, +35% if no damage was taken in the boss fight, +10% if none was taken on the whole floor.
- **Mutation Den** offers 2 Mutation pool items that cost heart containers (1, or 2 for quality 3+). You can't pay with containers you don't have, or buy yourself to death. Taking any Den item makes every later deal a Den.
- **Royal Chamber** offers a choice of 2 Royal pool items; taking one makes the other vanish. Otherwise Royal vs Den is 50/50.
- Debug: `deal royal|den`.

---

## 9. Hive hub (small)

A single screen of the restored Abandoned Hive. Most players should spend **under a minute** there.

| Interactable | Purpose |
|---|---|
| **Tunnel** | start a run: caste, seed (typed or random), Daily Run, Challenges |
| **Brood Roster** | choose playable caste |
| **Trove** | collection log (items, knick-knacks, fossils, fluids, enemies, bosses, brood, achievements) with field notes and unlock hints |
| **Larder** | pick 1 unlocked starting boon |
| **The Pulper / Hive Upgrades** | the Pulper turns banked materials into Pulp; spend Pulp on ~16–20 content-adding upgrades |

Rescued brood visibly fill the hive: normal brood as ambient wandering larvae and workers (density scales with population), mutated brood as named NPCs at a station doing their job. Resource-type milestones grow decorations (pulp walls, nectar pots, amber windows, mineral pillars).

---

## 10. Floor generation (Isaac algorithm)

### 10.1 Parameters (`/data/config/floorgen.json`)
```
grid: 13 × 9 (XL/Labyrinth: 13 × 9 still, double target)
start: (6, 4)
target_rooms = min(20, rand_int(0,1) + 5 + floor(depth * 2.6))   // depth = 1-based floor index
max_neighbors_for_new_cell = 1   // a cell is only added if it has exactly 1 filled neighbor
min_dead_ends = 1 (boss) + 2 (treasure, shop) + 1 (random special) + (brood cell rooms on floor 1 handled separately)
max_attempts = 200 (then relax neighbor rule; logged)
```

### 10.2 Algorithm
*(As implemented in M2: steps run at room level. A room's "neighbors" are its wall slots, `"ox,oy,D"`, and every door is an explicit link `slot → [room, slot]`, stored on both sides.)*
1. Queue ← [start]. Mark start filled.
2. Pop a room. For each of its wall slots (order shuffled by `RNG.stream("map")`):
   - skip if out of bounds, already filled, or `filled_count ≥ target`
   - skip if the candidate has more than 1 filled neighbor (prevents clumps and loops)
   - skip with 50% chance (keeps branches organic)
   - otherwise fill it and push it to the queue
3. When the queue empties: if `filled_count < target`, restart from scratch (new attempt, same stream, so it stays deterministic).
4. Collect **dead ends** (cells with exactly 1 neighbor, excluding start). If fewer than required, restart.
5. **Boss** = the dead end with the greatest BFS distance from start (ties → stream order).
6. Assign the remaining dead ends (shuffled) to: Dig Site, Trader, then (floor 1, 50%) a Brood Cell room, then one random special from the eligible set for this floor (`special_weights`, filtered by `special_rules`: Vault/Arcade from depth 3, Library needs the Archivist unlock). Contents and door kinds are then rolled by `FloorContents` in fixed room order (D26).
7. **Big rooms (2×1, 1×2, 2×2):** placed *during* growth (D25). When a new room is added, with `big_room_rate` (22%) it tries a big shape (weights `big_room_weights`) anchored so it covers the new cell. A room of any shape may only touch the existing map at exactly one cell edge, which keeps the room graph a tree. Specials, the boss and the start are always 1×1. L-shapes are deferred (D27).
8. **Secret room:** among empty cells with ≥3 filled neighbors (none of them boss), pick by stream. If none exist, relax to ≥2. Must not be adjacent to boss.
9. **Super-secret room:** empty cells with exactly 1 filled neighbor that is not boss/secret, and not adjacent to the secret room. Prefer the farthest from start.
10. **Floor 1 brood cells:** choose 2–4 normal rooms (not start, not boss-adjacent) and flag them `has_brood_cell`. Template choice must then use a template with a `brood_cell` slot.
11. **Template assignment:** per room, choose a template whose shape matches, whose `room_types` include the room's type and whose stratum is the floor's (or `"*"` for shared specials), weighted, via `RNG.stream("rooms")`. Rooms with sealed brood cells need the `brood_cell` tag; if no shape matches, the cell is dropped rather than failing. Difficulty bands come in M4.

### 10.3 Invariants (unit-tested)
- All rooms are reachable from start (BFS over doors).
- Boss is a dead end and its BFS distance == the maximum over dead ends.
- Each secret room borders ≥3 rooms (or ≥2 when relaxed, logged) and never borders the boss.
- Each super-secret room borders exactly 1 room, and that room is not the boss.
- Same seed + same floor + same unlock state → identical map (structural hash equality).
- Room count == target (doubled under Labyrinth/XL).

### 10.4 Room template format (`/data/rooms/<stratum>/<id>.json`)
Hand-authored and human-editable. An in-engine editor arrives in M2 (`/tools/room_editor.tscn`) and saves the same format.
```json
{
  "id": "hive_basic_01",
  "stratum": ["hive"],
  "shape": "1x1",
  "difficulty": 1,
  "weight": 1.0,
  "doors": ["N", "E", "S", "W"],
  "tags": ["brood_cell"],
  "grid": [
    ".............",
    ".R.........R.",
    ".............",
    "......B......",
    ".............",
    ".R.........R.",
    "............."
  ],
  "legend": { ".": "floor", "R": "rock", "B": "brood_cell", "X": "pit", "S": "spikes", "T": "tinted_rock", "#": "block", "D": "deposit_slot" },
  "spawns": [
    { "enemy": "twin_grub", "at": [3, 2] },
    { "enemy": "bloat_tick", "at": [9, 4], "champion_ok": true }
  ]
}
```
A 1×1 room interior is **13×7 tiles** of 16 px (208×112 logical px) plus walls, which fits the 640×360 logical viewport with HUD margins at 2× zoom via the camera. Larger shapes are multiples (2×1 = 26×7 + wall seam, etc.).

### 10.5 Alternate path and hidden exits
- Each chapter (1–4) has a hidden exit on floor B: a **cracked boss-room floor** (needs a Dig Charge) that leads to the alt-path chain once the Oracle is rescued. Before then it shows only cosmetic cracks.
- Alt chain: *Aquifer* (ch2 depth) → *Fault Line* (ch3–4 depth) → *Reactor Vault* (final). It also requires a multi-step key quest (Spelunky-style): a **Lead Seal** dropped by a Flooded Burrows mini-boss, carried to the Fault Line, and so on. Details are in M6.

---

## 11. Brood rescue

### 11.1 Lost brood (common)
- Floor 1 always has 2–4 **sealed brood cells** in normal rooms (plus a possible Brood Cell special room).
- A cell is invulnerable until the room is clear. Then it pulses and can be broken by shooting it (3 hits) or dashing into it.
- Freed larvae (1–3 per cell) wiggle toward the door the workers use, and the arriving workers carry them out. **The rescue banks immediately** (written to the meta save on the event, not on run end).
- Population milestones (5, 10, 25, 50, 100, 200, 350, 500 lost brood) give unlocks.

### 11.2 Mutated brood (rare, named, one-time)
They're found in Brood Cell rooms (ch2+), behind secret walls, or as rewards for conditional objectives. Each is a unique individual. The first rescue grants a permanent unlock, and they appear in the hive at a station. **Mutated brood also follow the player as a weak familiar for the rest of the run in which they're rescued.**

| # | Name | Role | Where / condition | Unlock |
|---|---|---|---|---|
| 1 | **Pip** | Scout | Topsoil Brood Cell room | floor 1 minimap shows special-room icons |
| 2 | **Marrow** | Nurse | beat a ch1 boss without damage | choose a starting health boon in the Larder |
| 3 | **Fizz** | Alchemist | Landfill/Sewer secret room | Strange Fluids identified once seen |
| 4 | **Quill** | Archivist | Library room (first visit ever) → appears at ch2+ | Library rooms + Fossil pool expansion |
| 5 | **Grit** | Excavator | behind a super-secret wall in Bedrock | +1 Dig Charge at run start; dig-themed items enter pools |
| 6 | **Haggle** | Trader | buy 10 shop items total (lifetime), then found in a ch2 Trader back room | expands Trader pool |
| 7 | **Brace** | Guard | win a Challenge room on ch3 without damage | unlocks a playable caste (Soldier) |
| 8 | **Murmur** | Oracle | reach the ch4 boss in under 25:00 | curse preview on floor entry; hidden alt-path exits visible |
| 9 | **Wick** | Lamplighter | Collapsed Mine, in Cave-in curse | Cave-in light radius +50%; Glowing items enter pools |
| 10 | **Tallow** | Cook | rescue 25 lost brood (lifetime), then appears on floor 1 | Larder gets 3 new boons |
| 11 | **Sprocket** | Tinkerer | Landfill Arcade jackpot | Arcade rooms unlocked + new arcade machines |
| 12 | **Hush** | Undertaker | Catacombs Curse room | Sacrifice Altar rooms + Cursed pool expansion |

The Trove shows silhouettes plus hints for brood you haven't found ("*Something small is crying behind the deepest stone.*").

---

## 12. Castes (characters)

| Caste | Unlock | Health | Twist | Starting kit |
|---|---|---|---|---|
| **Worker** (Yellowjacket) | default | 3 hearts | baseline; hauls +10% faster | 1 Dig Charge |
| **Soldier** | Brace (Guard brood) | 4 hearts | shots knock back hard; −fire rate | Bronze Arrowhead |
| **Paper Wasp** | beat ch2 | 2 hearts + 2 Chitin | can chew walls: dash into a cracked wall to open it (no charge needed), slow | Dead Phone (active) |
| **Hornet** | beat ch4 | 3 hearts | huge damage, short range, big body | Cracked Crown (variant: −1 cell) |
| **Cuckoo Wasp** | rescue 4 mutated brood | 1 heart + 2 Toxic Chitin | parasite: kills steal a stat point temporarily (decays per room) | Raw Geode |
| **Tarantula Hawk** | beat a boss in under 30 s | 3 hearts | stinger paralyzes (first hit stuns 1 s); flies | flight flag |
| **Queen** | beat ch6 | 4 hearts | cannot shoot; commands 3 drone familiars that inherit all shot modifiers | 3 drones |

**Mutated castes** (tainted equivalents, M6): each caste gets a reworked version unlocked by a secret objective on the alt path.

---

## 13. Meta-progression (items and unlocks first)

### 13.1 Achievements → unlocks
- **150+ achievements** at launch. Nearly every one adds content (item, knick-knack, fossil, fluid, room type, mutation, boon, curse, alt floor, caste).
- About **40% of items are locked** at the start. Early cadence: on average one unlock per run for the first 20 runs (Vampire Survivors cadence), achieved through many cheap goals ("kill 50 grubs", "break 20 rocks", "find your first secret room").
- Data-driven: `/data/achievements/<id>.json` = `{id, name_key, desc_key, hint_key, condition: {type, params}, unlocks: [{kind, id}], steam_api_name}`.
- Condition types (generic, counter-based): `stat_threshold` (lifetime counters), `boss_kill` (boss, caste, flags), `run_event` (floor reached, time, damage taken), `collection` (n items seen), `brood_rescued`, `compound` (all/any of others).
- The unlock pop-up shows at run end (and mid-run as a small toast) with art and "Added to the Dig Site pool!".

### 13.2 Completion marks
Per caste, a mark for each of: ch4 boss, ch5 boss, ch6 boss, alt-path final, Queen's Chamber, Hollow Swarm, Challenge-mode win, Daily win. Each mark unlocks a specific item. They're shown as stamps on the caste's Roster card.

### 13.3 Hive Upgrades (~18, mostly content, bought with Pulp)
Examples: *+5 items to Dig Site pool*, *Arcade rooms* (if not via Sprocket, cheaper path), *Shop restocks once*, *Start at Chapter 3* (shortcut after beating ch3, no achievements in shortcut runs), *+1 Larder slot choice*, *Haul speed +15%*, *Trove: show item pool*, and, late-game, **Brood Bond** (a starting perk: pick one already-rescued mutated brood to join you as a familiar from the start of the run, user decision Q7) … plus **the only stat upgrades in the game: +1 heart container (one time, max)** and *+3 starting Mana*. No trees.

### 13.4 Contamination Levels (Heat/Ascension)
Unlocked after the first true win (ch6). There are 15 stacking levels, each adding one modifier (faster enemies, more champions, less healing, curse every floor, shorter haul windows, Den deals cost more…). The rewards are cosmetic hive decorations, a Trove star and higher Daily score multipliers.

### 13.5 Challenges
20 preset runs with fixed rules, castes and seeds. Each unlocks an item. Unlocked progressively.

### 13.6 Daily Run
A seed from the UTC date (`hash("DEEPSTING-" + YYYYMMDD)`), fixed caste, one attempt per day, a local leaderboard now and a Steam leaderboard in M8. Score = depth + time + kills − damage.

---

## 14. Game loop
`Hive (pick caste/boon, <1 min) → Floor 1 Abandoned Hive (rescue lost brood) → clear rooms (workers haul) → items / secrets / mutated brood → floor boss → [Royal/Den offer] → trapdoor → … → die or win → banked Pulp and brood shown → unlock pop-ups → new content in pools → descend again`

---

## 15. UI, UX, accessibility
- **Screens:** main menu, settings (video/audio/controls/accessibility/gameplay), pause (run stats, items, **seed**), minimap (Isaac-style: visited/adjacent revealed, special icons, items reveal more), item pickup banner (name + one-line description), Trove, death/win screen with run summary and banked loot, unlock pop-ups, hive interactables.
- **Accessibility:** screen-shake slider (0–100%), hit-stop toggle, flash reduction, colorblind-safe bullet palettes (Deuteranopia/Protanopia/Tritanopia sets with shape coding), high-contrast projectiles (thick outline + dark backdrop ring), aim assist (free-aim stick snapping, off by default), hold-to-fire vs toggle-fire, text size scale, slower game speed (assist, disables achievements).
- **Controller-first UI:** every menu is focus-navigable. The first button gets focus on open, and B/Esc always goes back.
- **Localization:** every player-facing string is a translation key in `/translations/strings.csv`. No literal UI strings in code.

---

## 16. Technical architecture

### 16.1 Engine and project
- **Godot 4.7.x** (latest stable at the time of writing: 4.7.2), GDScript (typed), **Compatibility renderer** (OpenGL 3.3 / GLES3: the broadest Windows/Linux/Steam Deck support, and more than enough for 2D).
- **Logical resolution 640×360**, stretch mode `canvas_items`, aspect `expand`, so 1920×1080 = 3×, 1280×720 = 2×, and 1280×800 = 2× with +40 px extra vertical space (HUD absorbs it). Default window 1280×720. Physics at 60 ticks; VSync on; max FPS 60 for a locked 60.
- Typed GDScript everywhere. Warnings for untyped declarations are on.

### 16.2 Autoloads (order matters)
| Name | Responsibility |
|---|---|
| `Events` | global signal bus (decoupled systems) |
| `RNG` | seeded RNG with independent named streams (`map`, `rooms`, `items`, `enemies`, `drops`, `fx`, `misc`), derived per floor so streams never desync |
| `Platform` | Steam/no-Steam wrapper (achievements, cloud, leaderboards, presence). Falls back to stubs |
| `MetaSave` | versioned meta save (unlocks, counters, brood, pulp, settings ref), mid-run save file, migrations, atomic writes |
| `Content` | loads and validates `/data/**.json` into dictionaries indexed by id; the single gateway for content lookups |
| `Art` | resolves `res://assets/sprites/<category>/<id>.png`; generates placeholder textures if missing |
| `Audio` | buses, SFX/music by id (`res://assets/audio/sfx/<id>.ogg`), missing files are silent no-ops |
| `GameState` | app-level state machine (boot, menu, hive, run, paused), settings application, input bindings |
| `RunState` | current run data (seed, floor, player stats/inventory/consumables, flags) with `to_dict`/`from_dict` |
| `DebugConsole` | backtick console; dev builds only (`OS.is_debug_build()`) |

### 16.3 RNG and determinism
- The run seed is a 32-bit value displayed as 8 characters `XXXX XXXX` from a 32-symbol alphabet with no ambiguous characters (`0/O`, `1/I` removed).
- Stream seed = `FNV-1a-64(run_seed, stream_name, floor_index)`. Our own hash is used, not `String.hash()`, so it stays stable across engine versions.
- Rules: gameplay code **never** calls the global `randf()`/`randi()`. Visual-only randomness (particles, screen shake) uses the `fx` stream, which is allowed to desync.
- Room-local enemy RNG: `stream("enemies", floor)` is re-derived per room by `(floor, room_index)` so that visiting rooms in a different order doesn't change what spawns.

### 16.4 Data and content
- **Format: JSON** in `/data/<category>/<id>.json` (one entry per file, diff-friendly, hand-authorable). Mods (D16) mirror the same layout under `user://mods/<mod>/data/`. `Content` validates required fields at load, and `tools/validate_data.gd` runs the same validation from the CLI (also covered by tests).
- `.tres` is reserved for engine resources (themes, tilesets, particle materials).
- **Effects** are referenced by type key and implemented in `/scripts/effects/<type>.gd`, registered in an effect registry.

### 16.5 Art pipeline (swappable placeholders)
- Every sprite has a canonical path: `res://assets/sprites/<category>/<id>.png` (categories: `player`, `enemies`, `bosses`, `items`, `pickups`, `projectiles`, `tiles`, `props`, `ui`, `brood`, `workers`, `fx`).
- `Art.texture(category, id)` returns the PNG if present, otherwise a procedurally generated placeholder (a colored silhouette chosen by category, with a hash-derived hue per id). **Replacing art = dropping in a PNG with the same name.** No code changes.
- Animations: optional sprite sheets `<id>_<anim>.png` + `<id>.anim.json` (frame size, fps). Absent → static sprite with procedural squash/stretch.
- **2.5D:** Y-sort on the world node, a drop shadow (an ellipse sprite) under every actor and projectile, a fake Z (`height`) on projectiles that offsets the sprite up and shrinks the shadow, and wall tiles with a top face and a front face for depth.

### 16.6 Performance
- **Projectiles** are pooled and simulated in a single `ProjectileSystem` node (arrays of structs, no per-bullet nodes). They're drawn via `MultiMeshInstance2D` / batched `_draw`, with collision by spatial hash against enemies and player hurtboxes. Target: 500+ bullets at 60 fps on Steam Deck.
- Particles use pooled `GPUParticles2D` (`CPUParticles2D` fallback for Compatibility where needed).
- Enemies use `CharacterBody2D` with simple steering. Pathfinding uses a per-room `AStarGrid2D` (13×7).

### 16.7 Saves
- Directory: `user://save/` (single folder; small JSON files; Steam Cloud friendly).
  - `meta.json`: unlocks, counters, brood, pulp balance, completion marks, trove-seen sets, version.
  - `settings.json`: video/audio/controls/accessibility, bindings.
  - `run.json`: mid-run snapshot written on quit / floor start; deleted on death/win.
- Every file has `"version": N`. `MetaSave.migrate(data)` applies `_migrate_vN_to_vN+1` steps in order.
- **Atomic write:** write `<file>.tmp` → rename over the original, keeping `<file>.bak` of the previous good copy. On a load parse failure, fall back to `.bak`.

### 16.8 Input
Bindings are defined in code (`scripts/systems/input_bindings.gd`) from a default table and applied at boot, with overrides from `settings.json`. This keeps `project.godot` clean and makes rebinding a data operation.

### 16.9 Debug console (dev builds only)
Commands: `help`, `seed [s]`, `god`, `give <item>`, `spawn <enemy> [n]`, `goto <floor>`, `reveal`, `unlock_all`, `bank <n>`, `room <template_id>` (room-template test mode), `clear`, `content` (counts), `save` / `wipe_save`. Commands that need systems not built yet print "available from Milestone N".

### 16.10 Tests (GUT)
`/tests/unit/test_*.gd`. Run headless with
`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.
Required coverage: floor-gen invariants (M2), pool weighting/removal (M3), save/load round-trip and migration, RNG determinism and stream independence, projectile-modifier stacking (M3), content validation.

### 16.11 Platform / Steam
`Platform` exposes `unlock_achievement(id)`, `set_stat`, `upload_leaderboard_score`, `set_rich_presence`, `cloud_enabled()`. With no `Steam` singleton (GodotSteam GDExtension absent) it logs and no-ops. GodotSteam is added in M8 with the App ID.

---

## 17. Milestone plan with acceptance criteria
| M | Scope | "Done" means |
|---|---|---|
| 0 ✅ | GDD, project, autoloads, folders, CLAUDE.md, GUT, console, data/i18n/art scaffolding | project boots to the main menu; tests green; GDD reviewed |
| 1 ✅ | Vertical slice: Abandoned Hive floor (fixed or simple gen), movement/dash/shoot, health, doors, 4 enemies + 1 boss, deposits + worker haul, brood cells, Dig Charge + 1 secret wall, 10 items (stat, projectile mods, familiar, active), minimap, death + restart | playable start-to-boss loop in under 10 min |
| 2 ✅ | Full floorgen + all special rooms, 40 ch1 templates, room editor, curses, Royal/Den, Trader | invariant tests green; seeds reproduce |
| 3 ✅ | Generic modifier stack at scale, all pools, trinkets, fossils, fluids, radiation + mutations, 60 items, synergy test scene | stacking tests green; 500-bullet perf test passes |
| 4 ✅ | Ch1–4 + alts, 3 bosses/chapter, champions, difficulty curve, first ending | full run to ending 1 |
| 5 | Achievements → unlocks, pool locking, completion marks, 6 mutated brood, hive + Pulper, Trove, Hive Upgrades, 3 castes, save/resume | fresh save → unlocks flow across runs |
| 6 | Ch5–6, alt path, secret bosses, mutated castes, Contamination, challenges, Daily, 120+ items | content complete |
| 7 | Polish and accessibility, rebinding UI, palettes, SFX hooks, perf, Deck check | Deck 1280×800 at 60 fps |
| 8 | GodotSteam, achievements, cloud, leaderboards, exports, credits, store asset checklist | Steam build uploads |

---

## 18. Naming and IP rules
- All names, art, text and audio are original. No names from Isaac, Gungeon, Hades, etc. appear in game files (they appear only in this document as design references).
- New item names go through a quick search check before being finalized for the store build (M8 checklist).

---

## 19. Decisions log
| # | Decision | Why |
|---|---|---|
| D1 | Godot **4.7.2**, Compatibility renderer | latest stable; broadest GPU support for 2D on Windows/Linux/Deck |
| D2 | Logical res 640×360, `canvas_items` + `expand` | clean 2×/3× at 720p/1080p; 1280×800 gains vertical space instead of letterboxing |
| D3 | Content as **JSON**, one file per entry | hand-authorable, diffable, validator-friendly; `.tres` only for engine resources |
| D4 | Fire Rate stored as **shots/second** | easier to reason about and display than Isaac's "tear delay" |
| D5 | **Superseded by user decision:** all banked materials go through the Pulper and become **Pulp**, the single meta-currency | user answer to Q4 |
| D6 | **Superseded by user decision:** hauls go to a floor stash, lost on death, banked when the swarm carries it up the boss shaft | user answer to Q3 |
| D7 | **Superseded:** in-run currency is **Mana** (Chip 1 / Fragment 5 / Chunk 10 / Crystal 25), from pickups only | user decision |
| D8 | Projectile modifiers ordered by fixed priority, not pickup order | deterministic, testable, order-independent builds |
| D9 | Projectiles simulated in one system node with arrays, not per-bullet nodes | required for 500+ bullets at 60 fps |
| D10 | Own FNV-1a hashing for seed derivation | `String.hash()` isn't guaranteed stable across engine versions |
| D11 | Room interior 13×7 tiles @16 px (Isaac proportions) | proven room proportions; fits the logical viewport with HUD |
| D12 | Input map defined in code, not `project.godot` | rebinding is a data operation; clean diffs |
| D13 | GUT 9.6.1 vendored in `addons/gut` | headless-runnable test framework; pinned version |
| D14 | Brood rescue persists to disk on the rescue event | spec says "banked immediately, not lost if you die" |
| D15 | Mutated brood familiars only in the run they're rescued; a late-game **Brood Bond** upgrade lets you pick one to start with | user answer to Q7 |
| D16 | Data-only mods: `Content` also loads `user://mods/<mod>/data/<category>/**.json` when `settings.gameplay.mods_enabled` is true; a mod entry with an existing id overrides it | Q5 answer; costs nothing now |
| D17 | Aim mode `auto` (default): arrow keys snap to 4 directions (Isaac), mouse and right stick aim freely | best default per device |
| D18 | One room is instantiated at a time; all per-room state lives in the floor layout dict | simple and save-friendly |
| D19 | Pedestal items and the boss are rolled at floor-generation time, in fixed room order | exploration order can't change what a seed gives |
| D20 | Enemies/drops use per-room RNG streams `(seed, floor, room_index)` | same seed gives the same fights in any visiting order |
| D21 | Validator rule: door entry lanes and spawn tiles must be walkable | stops templates from trapping the player in rocks |
| D22 | Enemies get a 0.5 s wake-up on room entry, plus a 0.45 s spawn-in animation | Isaac-fair room entries |
| D23 | Player shots stay amber-family; item tints blend at most 45% | bullet readability (§7.1) |
| D24 | Dig Charge: 38 px radius, 60 damage, 1 heart to the player if caught | rescaled for 16 px tiles (Isaac ≈ 2.5 tiles) |
| D25 | Big rooms are grown during generation, at room level, with the "touch the map at exactly one edge" rule | merging cells afterwards can't make 2×2 rooms (the cell tree never has a 2×2 block) and breaks dead-end math |
| D26 | `FloorContents` rolls every room's contents and door kinds at generation time, in room order; deal rooms roll when they appear | exploration order can't change a seed's floor; same seed = identical layout + contents (tested) |
| D27 | L-shaped rooms deferred; shapes are 1×1, 2×1, 1×2, 2×2 | rectangles cover most of Isaac's value; L needs non-rect walls and camera rules |
| D28 | Locks: Trader from floor 2, Dig Site from depth 3, Vault 2 Royal Jelly, Library 1 | gives Royal Jelly a real use from chapter 1 (answers part of Q9) |
| D29 | Chapter 1 = The Abandoned Hive → Topsoil (`config/floorgen.chapters`); clearing Topsoil ends the run as "Chapter 1 complete" until M4 adds chapters 2–4 | playable to a clear end every milestone |
| D30 | Special rooms are plug-ins: `scripts/run/specials/<type>.gd`, created by the room by type, with hooks `setup`, `on_enemies_cleared`, `on_cleared` | adding a room type never touches Room |
| D31 | Tremor = "only visited rooms on the map" (simpler than a shuffling map); Labyrinth = XL floor + 2 Dig Sites, no floor skip yet | readable now; the skip returns when chapters have more floors |
| D32 | Statuses: poison (1.25 dmg / 0.5 s for 3 s) and slow (½ speed for 2 s); bosses get shorter durations | first element effects for item builds |
| D33 | Projectiles, blasts and bursts only affect nodes inside the current room | a room being freed on the same frame could otherwise absorb hits (found by the smoke test) |
| D34 | Brood Cell rooms use a shared template (any stratum); Mutation Den can't kill you or take containers you don't have | design says Brood Cells are "rare outside floor 1"; Isaac-fair deals |
| D35 | Everything owned is an effect source: items, the active, the knick-knack and mutations all go through one `EffectHost.rebuild()` | one code path for stats, shots, hooks and familiars |
| D36 | Event hooks are data: `trigger` effects `{event, chance, per_luck, action}` with events kill / room_clear / floor_start / damage_taken and a shared action library | on-kill / on-clear / on-hurt items need no code |
| D37 | On-hit procs are data: `proc` effects (crit, chain, stun, element, knockback) rolled per hit on the `misc` stream, luck-scaled | generic, testable, stack with every modifier |
| D38 | New projectile modifiers: multishot (adds shots, cap 7, widest spread wins), boomerang, wave, knockback; split children never boomerang or multishot | keeps combinations bounded and readable |
| D39 | One fossil/fluid slot (a second slot comes with an item later); picking one up while holding one drops the old one, which stays inert until you step away | Isaac's card/pill swap without the swap-loop bug |
| D40 | Strange Fluids: 10 vial colors mapped to 12 effects per run from a run-level seeded stream; identified for the run when drunk; stat fluids are permanent `perma_stat` changes | seeded, readable, Isaac pill model |
| D41 | Radiation: kills add the enemy's `radiation` (bosses 20), glowing contamination tiles (`G`) add 5/s; thresholds 60, 90, 120...; the pick appears at the next room clear (or right away if the room is already clear) | never interrupts a fight |
| D42 | Synergy callout is generic: an item synergizes when its build tags (modifiers / proc kinds) pair with an owned tag in `config/synergies.json` | no item pairs are hand-listed |
| D43 | Knick-knacks share ItemPool rules (no repeats in a run) via a single "trinkets" pool | reuse, determinism |
| D44 | `config/floorgen.chapters` lists floor slots `{main, alt, final_boss?, ending?}`; the alternate is picked by a seeded roll per (seed, floor) at `alt_chance` 33%. `alts_require_unlock` is false until Milestone 5's achievements gate them | alternates are playable now; flipping one flag gates them later |
| D45 | Difficulty curve in `config/difficulty.json`: enemy HP +10%/floor (bosses half that), enemy shot speed +3%/floor, champion chance 5% +1%/floor (cap 40%), template difficulty bands 1/1/2/2/2/3/3/3, hits do a full heart from floor 7 | one tunable file; tested |
| D46 | Champions: 8 data-driven types (tough, fast, shielded, regenerating, volatile, toxic, splitting, radiant). Each wears a pulsing colored ring plus a light tint, always drops a pickup and gives 5× radiation (radiant 10×). Bosses, boss minions and split children are never champions | readable at a glance; not color alone (the ring pulses) |
| D47 | A boss already met this run isn't rolled again if another fits the stratum | Isaac-like variety across a chapter |
| D48 | The last floor's boss is fixed (`final_boss`); beating it and taking the trapdoor ends the run with that floor's `ending` screen (story text) and records it in the meta save (v3 adds `endings`) | the first ending; deeper chapters will move the ending down |
| D49 | Chapters 2–4 room templates are a scripted first pass (mirrored layouts per stratum flavor, enemies kept away from door lanes); refine them in the room editor | gets every floor playable now; hand-tuning comes from playtesting |
| D50 | The mutation pick also opens as soon as the meter fills while you're in an already-cleared room | completes D41 (a smoke test found the gap) |
| D51 | Item labels (user request): walking within ~2 tiles of a pedestal, ware or pickup shows a HUD side panel (under the minimap) with its name, type, quality, effect and price. Actors opt in with group `inspectable` + `inspect_info()`; text comes from `scripts/ui/inspect.gd`; the Toxic Fog curse still hides items | identify things before committing to them; one generic path |

---

## 20. Open questions
All eight Milestone 0 questions were answered (2026-11-04):

| Q | Answer | Where it landed |
|---|---|---|
| Q1 Art | **16-bit-style pixel art, 16 px tiles**, 640×360 canvas | D2, D11; placeholders built to that grid |
| Q2 Co-op | **Much later.** Ship single-player; keep RunState/Player free of single-player-only shortcuts where it's cheap | — |
| Q3 Banking | **Floor stash, lost on death.** Defeating the boss opens a way up, and you watch the swarm carry the floor's loot out | §5.2, D6 |
| Q4 Currency | In-run: **Mana chits** (Chip/Fragment/Chunk/Crystal = 1/5/10/25). Meta: everything goes through **the Pulper** into **Pulp** | §4, §5.1, D5, D7 |
| Q5 Mods | **Yes.** Data-only mod loading from `user://mods/<mod>/data/` is reserved now (off by default, `gameplay.mods_enabled`) | §16.4, D16 |
| Q6 Title | **DeepSting**, tagline *"Stung too deep."* | §0 |
| Q7 Brood familiars | Only in the rescue run, until a late-game **Brood Bond** perk lets you pick one to start with | §13.3, D15 |
| Q8 Leaderboards | **Steam only** | §13.6 |
| Extra | Health stays **hearts**; **Chitin** = soul-heart shields; **Toxic Spined Chitin** = black hearts; **Royal Jelly** = keys for now | §3.4, §4 |

### New open questions (Milestone 4)
3. **Q11: Alternate floors before unlocks.** Alternates (Flooded Burrows, Sewer Pipes, Collapsed Mine, Catacombs) show up 1 in 3 times right now. The design gates them behind achievements; Milestone 5 can switch that on (`alts_require_unlock`). Gate them, or keep them in from the start?
4. **Q12: Run length.** A full run is now 8 floors. Isaac's first ending also sits around 8 floors. Does that pace feel right once you play it, or should chapter 1 be a single floor?

### New open questions (Milestone 1 review)
1. **Q9: Royal Jelly's second use.** M2 added Mana sinks (the Trader, Arcade machines) and Royal Jelly locks (Trader from floor 2, Dig Site from depth 3, Vault, Library). Do you still want a second Royal Jelly use (e.g. feeding rescued brood for a bonus)?
2. **Q10: Shaft haul pacing.** The shaft sequence takes ~3–6 s depending on stash size, and the trapdoor appears only afterwards. Too slow? It can be skipped by leaving the room.
