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
- **Pins** scale with heist, 3–8. Every 5th **heist** is golden: +1 pin, 2× loot, gold door, Good window +3°.
- **Dial speed / window** use a sawtooth on the heist index (squeeze, then a golden breath). DDA bends up to 15% easier but only 8% harder. Wide Gate adds +1.5° to Good per level (cap 5).
- **Direction flips** from heist 2, once per new door, with a 0.4 s chevron telegraph. No mid-door random flips.
- Target lead is **120–270°**. Target heist length: 20–30 s.
- **Vault tricks** (`GameState.trick_for`): one twist on the same tap, for all three doors of a heist. Each is introduced alone (Good +2° that heist), then rotates with plain heists; golden heists never carry one.
  - Heist 4 **slide**: the gate creeps against the pick at 0.06 rev/s; green chevrons show which way.
  - Heist 7 **double**: a second gate (outlined) waits 110–170° past the first; hit both in one sweep, no respawn between.
  - Heist 11 **dark**: wall and door dim; the gate and tumbler only show inside a warm wedge 80–140° ahead of the pick.
- **Vault types** by door index: 1 Piggy, 3 Office, 6 Bank, 11 Museum, 26 Casino, 51 Fort Knox. The wall color behind the door changes with the type.

---

## 3. Forgiveness, alarm, and the bribe

| Event | What happens |
|---|---|
| Miss / Near-Miss | Alarm +1 (lamp lights, short red flash, pin ejects, dial jams ±3° for 200 ms). A **miss ghost** keeps the old gate (green), a white gap to where the pick stopped and a red stop tick on the dial for 0.45 s, then fades over 0.35 s, past the respawn. Seated pins are kept. The same vault keeps spinning. |
| Third strike | Spotlight hardens + strobe + siren. Heist 1 cuts the light (no strobe, no bust). Heist 2+: `busted` → the guard's arm shoots out and a handcuff snaps shut on the pick tip (0.3 s reach, 0.12 s close, metal click, 0.4 s hitstop, camera 1.12x toward the pick). 0.9 s later `revive_offered` → **Bribe the Cops** over that frozen frame. A bribe releases the cuffs; a bust keeps them under the card. |
| Bribe taken | Alarm resets, 3-2-1 countdown, same vault continues with its seated pins. |
| Bribe skipped | `run_ended("caught")` → BUSTED card → Try Again on the same vault. |
| Bribe offer | No body text: handcuffs inside a red ring that drains in 5 s, one gold BRIBE button, a faint "get caught". The last two seconds tick and pulse 4%; at zero the cops win. Tapping the dim no longer skips. |
| Clean door | A door cracked with no strike turns one lamp off (`GameState.lower_alarm`); the guard settles a step. |
| Mercy | The same door lost twice in a row opens its Good gate +3° until it cracks (`GameState.mercy_deg`). |

Near-Miss keeps the heavier 180 ms hitstop so the almost-win still lands harder than the win.

---

## 4. Loot, meta, and retention

- **Single currency: cash ($).** Pins drop cash directly (`pin_cash`). Each door also pays `40 + 12 × door` (×2 on golden). No hidden score.
- **Window silhouette** shows the next hideout item. Door open → the item pops and flies into the bag; gold/gem rain still falls.
- **End-of-heist card** (opaque `#0B1020` panel, gold rim): `HEIST N CRACKED`, a 60 px loot roll (the bag bumps 8% at every fifth), the hideout ring with the next item as a silhouette (new item in colour, 1.0 → 1.2 → 1.0 pop; tap opens the room), a 76 px `NEXT HEIST`, `3x LOOT`, then one row: `FREE` glove (every 4 heists) · Market · Stash. No subtitle or shelf text.
- **City strip** (card top, `CityStrip.gd`): piggy shop → office → bank → museum → casino → Fort Knox → **moon vault** (door 100). Cracked cities in colour, the current one ringed in gold, the ones ahead as silhouettes; crossing into a new city pops its icon.
- **Daily Big Heist**: once a day (UTC) after the first heist, a gold `BIG HEIST x5` button above NEXT. One golden door at 5x loot plus a guaranteed glove (or $500 once all are owned); retryable until cracked; does not move the career door index.
- **Hideout shop (the cash sink)**: one free item per heist for heists 1–3, then every item is bought. Prices climb x1.6 per slot ($650 … ~$70k) and each owned item adds +2% to all cash (12 = +24%). The next slot breathes when affordable; the card's shelf ring shows a gold "$" coin. Save v3 players keep the items the old every-3-heists drop gave them. Simulated (avg player, no crew stash): a purchase every 3–6 heists through heist 30, the last two around 35–40.
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
- Alarm: lamps + guard (painted: asleep at the desk → alert looking ahead on strike 1 → head up, flashlight raised at the dial on strikes 2-3).
- Alarm (code fallback): lamps + guard. Strike 0 asleep (Zzz), 1 head up + "!" (no red edge strip any more: it read as a rendering bug), 2 on his feet with a flashlight sweeping the dial, 3 stepped out with the beam locked on the dial + strobe. Heist 1: he looks up on strike 3 and dozes off again.
- Combo ≥ 3: gold trail on the pick, not a HUD number.
- The equipped glove (painted fist, `assets/art/glove_<id>.png`) grips the pick and clenches 8% on every Perfect. Market shows the eight gloves as an icon grid (drop-only gloves read "Drop").
- **Glove perks** (one small, readable effect each, shown under the icon in the Market): leather – starter · latex – Perfect slice +10% · gold – pin cash +10% · neon – Hot Hands after 3 Perfects · skeleton – the first miss on each door doesn't sound the alarm · crimson – 1 s bribe restart instead of 3-2-1 · ice – dial 5% slower · royal – golden vaults pay x3 loot. Bot check (σ 50 ms, 10 tries, no bribes): heist 6 busts 1/10 with every glove; heist 11 (dark) 9/10 leather vs 8/10 skeleton/ice/latex – a nudge, not a skip.
- **Hot Hands meter** (`HotMeter.gd`, under the grade word): one flame per Perfect needed; each Perfect lights the next (pop 1.35), a strike breaks the row in red. Lighting it drops a full-width "HOT HANDS! / x2 CASH" banner for 1.4 s, then a breathing flame + x2 badge while it burns.
- **Hot Hands**: 4 Perfects without a strike (across doors; a Good neither counts nor breaks it) → 80 ms freeze, orange burst, rising arpeggio, flickering fire ring on the dial, double-length orange pick trail, octave-up layer on every hit. Pins pay **2x** until any strike (glass-snap) or the heist ends. Orange, not gold: the full gold dial stays reserved for the golden heist.
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

## Art (Canva)

Door, guard (asleep / alert), loot bag, the 12 hideout items, six room backgrounds (one per vault type), button and panel skins, and the app icon were generated with Canva's image generator, background-removed there, and exported from the Canva design "Vault Heist game sprites" as 1080 px PNGs. `tools/art/prepare_art.gd` turns that export into the committed game assets (trim, resize, a clean porthole cut in the door, the painted beam cut off the alert guard so `Guard.gd` can aim its own, `assets/ui/game_theme.tres` with nine-slice buttons and panels):

```bash
CANVA_DIR=/path/to/export godot --headless --path . -s res://tools/art/prepare_art.gd
godot --headless --path . --import
STEP=theme godot --headless --path . -s res://tools/art/prepare_art.gd
```

Every art consumer falls back to the old procedural drawing when its file is missing. The steel door carries the career as a tint (`VaultSprites.door_tint`: rust, then the metal stops). The project theme is set in `project.godot` (`gui/theme/custom`); gold primary buttons use the `PrimaryButton` variation.

## Analytics

`scripts/autoload/Analytics.gd` builds the events a publisher test reads (GameAnalytics naming): progression Start/Complete/Fail per heist (`heist_013`, `daily`), and design events `heist:busted`, `heist:seconds`, `bribe:offered|taken|declined`, `ad:<placement>:rewarded|failed`, `hideout:item:<id>`, `glove:equip:<id>`, `hot_hands:lit`, `session:start|end`. If the GameAnalytics Godot plugin is installed (native `GameAnalytics` singleton, game key in its config) every event is forwarded; debug builds also append them to `user://analytics.jsonl`. No SDK is vendored.

## Store package

- `docs/store/listing_en.md`, `listing_tr.md`: title, short and full description, keywords.
- `docs/store/screenshots/store_01..05.jpg`: 1080x1920, captioned in the Canva design "Vault Heist store screenshots" from stills rendered by `tools/store/StoreShots.gd` (`OUT=<dir> godot --path . --fixed-fps 30 -s res://tools/store/StoreShots.gd --resolution 720x1280`).
- `export_presets.cfg`: Android, arm64, immersive, `com.avaregamestudio.vaultheist`, APK to `build/` (signed with the editor's debug keystore until you set a release one; switch to Gradle + AAB for Play).

## Ad capture (CPI test creative)

`tools/ad_capture/AdCapture.tscn` plays a scripted ~30 s cut of the real game with a director instead of a player, and never writes the save (`GameState.no_save`):

| Time | Beat |
|---|---|
| 0–4 s | Hook: two lamps lit, guard on his feet, one clean pin, then a late tap → third strike → cuffs snap on the pick |
| 4–15 s | Heist 7 (double gate), doors 2–3: chained gates, Hot Hands ignites, doors fly |
| 15–27 s | Golden heist, last door: gold dial, fire ring, hoard rain, card rolling the loot |
| 27–30 s | Hold on the card (`NEXT HEIST` is the call to action) |

Record a full-size mp4 (works on a laptop screen, no ffmpeg; macOS with the Swift toolchain):

```bash
mkdir -p /tmp/ad/frames
AD_FRAMES=/tmp/ad/frames godot --path . --write-movie /tmp/ad/mm.png --fixed-fps 30 --resolution 720x1280 res://tools/ad_capture/AdCapture.tscn
swift tools/ad_capture/encode_mp4.swift /tmp/ad/frames /tmp/ad/mm.wav ad.mp4 30
```

`AD_FRAMES` renders the game in a 720x1280 SubViewport and saves a JPG per frame; Movie Maker's own (window-sized) PNGs can be deleted, its `mm.wav` is the audio. Without `AD_FRAMES`, `--write-movie ad.avi` records the window as MJPEG AVI. Keep `tools/` out of export presets.

## Next production steps

1. Swap mock ads for a mediation SDK and store IAP receipts.
2. More production samples: siren and Hot Hands arpeggio are still procedural. Pin click, door slam, loot landing, miss clunk, cuff click and glass snap are CC0 Kenney samples in `assets/sfx/` (see its LICENSE.txt); drop a `name_N.ogg` there to add a variant.
3. Telemetry: grade histogram, bribe conversion, time-to-second-session.
4. Android export: portrait, immersive, texture compression already flagged in `project.godot`.
