# Loop Engine — Vault Heist

Hyper-casual **one-tap** vault cracker for Godot **4.6**. Tap when the pick sits in the gate to seat a pin; seat every pin and the door swings, the prize flies into the bag. **One heist = three doors.** The card waits until the heist is done. Door art (rust → steel → copper → gold → gem-set) is a persistent career.

Behavioral systems (variable-ratio jackpots, three-strike alarm with a rewarded "Bribe the Cops", unfinished hideout shelf, DDA flow bend) stay first-class nodes.

Open `project.godot` in Godot 4.6, press Play. Click / tap / space when the pick is in the green gate.

---

## 1. Scene tree and files

```
Main.tscn                          boot composition
├── GameWorld.tscn                 dial, input, DDA, VR, juice
│   ├── Camera2D
│   ├── Arena (RingArena.gd)       vault door + dial, prize window, cuff, bolts
│   │   ├── LockPin                tumbler: seat bounce, gold pin, eject on miss
│   │   ├── Pointer (RingPointer)  pick + short combo trail
│   │   └── Burst (GPUParticles2D)
│   ├── Guard                      dozing guard at a desk; wakes one step per strike
│   ├── InputProcessor             one verb: press = lock
│   ├── MetaUpgrade                Crew (offline stash) + Wide Gate
│   └── Juice                      hitstop / shake / loot fly / alarm / haptics
├── UIManager.tscn
│   ├── HUD                        door pips · lamps · grade word · loot bag (no buttons in play)
│   ├── Card                       end-of-heist: CRACKED / BUSTED, loot roll, hideout, 3x ad, Market · Stash
│   ├── RevivePopup.tscn           third strike → Bribe the Cops (rewarded) or Get Caught
│   ├── SettingsPopup.tscn         language / sound / vibration (+ Auto-Crack if purchased)
│   ├── MarketPopup.tscn           Crew, Wide Gate, cuff skins
│   ├── HideoutPopup.tscn          12-item room
│   └── ClaimPopup.tscn            Crew stash collect (card Stash button only)
├── SoundManager.tscn              procedural tones
└── AdsManager.tscn                mock rewarded mediation

Autoloads: EventBus, Settings, GameState, TimeScale (sole writer of Engine.time_scale), OverlayPause
```

| Path | Role |
|---|---|
| `scripts/autoload/GameState.gd` | Persistent door index, heist math (3 doors), cash, alarm, sawtooth curve, gloves, hideout |
| `scripts/world/GameWorld.gd` | Heist loop: spin → tap → pin → door → next door ×3 → card. Strikes, bribe, 3x boost |
| `scripts/core/TimingEngine.gd` | Angle delta → Perfect / Good / Near-Miss / Miss, plus per-hit pitch and haptic profile |
| `scripts/behavioral/DynamicDifficulty.gd` | Flow-channel tuner; bends the stage curve ±15% |
| `scripts/behavioral/VariableRatioSchedule.gd` | Skinner VR payouts / jackpots |
| `scripts/behavioral/ZeigarnikTracker.gd` | Needle-passed-the-pin tension + loot shelf tease |
| `scripts/meta/MetaUpgrade.gd` | Crew (offline cash), Wide Gate (+1.5° Good arc / level, cap 5) |
| `scripts/ui/UIManager.gd` | HUD + end-of-heist card |
| `scripts/ui/LootBag.gd` | Duffel bag: rolling cash number, gold fill, bounce on loot |
| `scripts/ui/AlarmLamps.gd` | Three wall lamps, no text |
| `scripts/ui/DoorPips.gd` | Three door icons: cracked gold, current steel, ahead dark |
| `scripts/ui/QuestRing.gd` | Unfinished ring for the next hideout item (card only) |
| `scripts/ui/RevivePopup.gd` | Bribe the Cops |
| `scripts/vfx/VaultSprites.gd` | Painted door per vault, tumbler, tap hand, gold bar, gem |
| `translations/strings.csv` | EN / TR strings |

Portrait canvas: **720×1280**, `canvas_items` stretch, mouse-emulated touch.

**Localization.** Every player-facing string is a key in `translations/strings.csv`. Code-set texts go through `tr()` and re-render on `NOTIFICATION_TRANSLATION_CHANGED`. Do not call `to_upper()` on translated text (Turkish `i` → `İ`); write uppercase into the CSV instead.

---

## 2. Level structure (one heist = three doors)

- `current_stage` is the persistent **door** index. A bust retries that door; a crack moves on. The end card waits until `_doors_goal` doors of the current heist are cleared (`DOORS_PER_HEIST = 3`).
- **Heist 1 cannot be failed.** The guard still walks in; `raise_alarm` never returns caught.
- **Pins** scale with heist, 3–8. Every 5th **heist** is golden: +2 pins, 2× loot, gold door, Good window +3°.
- **Dial speed / window** use a sawtooth on the heist index (squeeze, then a golden breath). DDA still bends ±15%. Wide Gate adds +1.5° to Good per level (cap 5).
- **Direction flips** from heist 2, once per new door, with a 0.4 s chevron telegraph. No mid-door random flips.
- Target lead is **120–270°**. Target heist length: 20–30 s.
- **Vault types** by door index: 1 Piggy, 3 Office, 6 Bank, 11 Museum, 26 Casino, 51 Fort Knox. The wall color behind the door changes with the type.

---

## 3. Forgiveness, alarm, and the bribe

| Event | What happens |
|---|---|
| Miss / Near-Miss | Alarm +1 (lamp lights, short red flash, pin ejects, dial jams ±3° for 200 ms). A **miss ghost** keeps the old gate (green), a white gap to where the pick stopped and a red stop tick on the dial for 0.45 s, then fades over 0.35 s, past the respawn. Seated pins are kept. The same vault keeps spinning. |
| Third strike | Spotlight hardens + strobe + siren. Heist 1 cuts the light (no strobe, no bust). Heist 2+: `revive_offered` → **Bribe the Cops**. |
| Bribe taken | Alarm resets, 3-2-1 countdown, same vault continues with its seated pins. |
| Bribe skipped | `run_ended("caught")` → BUSTED card → Try Again on the same vault. |

Near-Miss keeps the heavier 180 ms hitstop so the almost-win still lands harder than the win.

---

## 4. Loot, meta, and retention

- **Single currency: cash ($).** Pins drop cash directly (`pin_cash`). Each door also pays `40 + 12 × door` (×2 on golden). No hidden score.
- **Window silhouette** shows the next hideout item. Door open → the item pops and flies into the bag; gold/gem rain still falls.
- **End-of-heist card**: `HEIST N CRACKED`, loot roll, hideout ring (tap opens the room), `NEXT HEIST`, `3x LOOT`, optional `WATCH FOR GLOVES` every 4 heists.
- **Hideout**: 12 items. One per heist for the first three heists, then one every 3 heists. Tap the card shelf or the market hideout line.
- **Market**: Crew (offline cash), Wide Gate (visible green-arc widen), glove skins. Combo is a pick trail from x3, not a number. Variable-ratio drops arm a **gold pin** instead of an x8 label.
- **Crew stash**: card button only (next to Market). The Claim popup no longer auto-opens on focus.
- **Auto-Crack** is IAP-only.
- **Meta unlocks one system at a time.** Heists 1–3: dial + hideout only. The card closing heist 3 shows a gold `NEW! Market` (Wide Gate, glove skins); the card closing heist 5 shows `NEW! Hire a crew` and the crew starts stealing from then on (no back-pay). Constants: `GameState.MARKET_UNLOCK_AFTER`, `CREW_UNLOCK_AFTER`.

---

## 5. Juice (what fires on what)

- Perfect: 60 ms hitstop → 7 px shake → zoom 1.05 → dial bounce 1.08 → gold burst → pin flash → glow pulse. Pin seat bounce 1.0 → 1.3 → 1.0 in 120 ms. Door-seam crack light grows with `pins / needed`.
- Good: same chain without hitstop, smaller numbers.
- Near-Miss: 180 ms hitstop, 14 px shake, siren pitch sliding 1.0 → 0.7 over 400 ms.
- Miss: 18 px shake, dial jam, pin eject, low clunk.
- Door open: 100 ms freeze → hinge swing → rust flakes / shell chips → prize flies to the bag → gold + gem rain → "ka-chunk" then "cha-ching".
- Alarm: lamps + guard. Strike 0 asleep (Zzz), 1 head up + "!", 2 on his feet with a flashlight sweeping the dial, 3 stepped out with the beam locked on the dial + strobe. Heist 1: he looks up on strike 3 and dozes off again.
- Combo ≥ 3: gold trail on the pick, not a HUD number.
- **Hot Hands**: 5 Perfects in a row (across doors) → 80 ms freeze, orange burst, rising arpeggio, flickering fire ring on the dial, double-length orange pick trail, octave-up layer on every hit. Pins pay **2x** until any strike (glass-snap) or the heist ends. Orange, not gold: the full gold dial stays reserved for the golden heist.
- Approach inside 45°: rising drone, cut on tap.

Guidelines for production art:

1. One dark field (`#0B1020`), one accent (green gate), one danger (red), one loot (gold).
   The gate ring sits on a 36 px `#0B1020` track (85%) so door art never shows under the pick. Gate 26 px, Perfect slice 10 px.
2. Hit feedback is **time** (hitstop) before **particles**.
3. Near-miss uses *longer* hitstop than Perfect.
4. Golden vault is the only time the whole dial may go gold.
5. Keep GPUParticles `one_shot` + `explosiveness = 1`.

---

## 6. Monetization (mock)

| Placement | Trigger | Reward |
|---|---|---|
| `near_miss_revive` | Third alarm strike | Bribe the Cops: alarm reset, vault continues |
| `end_multiplier` | Card `3x LOOT` | Twice the heist's banked cash again |
| `glove_drop` | Card every 4 heists | Random unowned glove |
| IAP `no_ads_bundle` | Shop | Skip non-revive ads, 3x auto-claimed |
| IAP `auto_tap` | Shop | Auto-Crack: crew taps the Good window |
| IAP `dial_obsidian` | Shop | Neon gloves |

`AdsManager` waits `mock_latency_ms` then emits `ad_finished`. Replace `show_rewarded` with AdMob / LevelPlay; keep the EventBus contract.

---

## Retention mapping (design hypotheses)

| Lever | System |
|---|---|
| D1 | Persistent heist number + unfinished hideout room + heist 1 cannot fail |
| Session length | 20–30 s heists (3 doors), one-tap continue, golden heist every 5th |
| D7 | Door art career, glove skins, crew stash drip, 12-item hideout |

Instrument `EventBus.tap_evaluated` / `run_ended` / `revive_resolved` before claiming numbers.

---

## Next production steps

1. Swap mock ads for a mediation SDK and store IAP receipts.
2. Production samples for pin click / door hinge / loot land (procedural tones are the prototype).
3. Telemetry: grade histogram, bribe conversion, time-to-second-session.
4. Android export: portrait, immersive, texture compression already flagged in `project.godot`.
