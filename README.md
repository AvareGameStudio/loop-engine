# Loop Engine — Vault Heist

Hyper-casual **one-tap** vault cracker for Godot **4.6**. Tap when the pick sits in the gate to seat a pin; seat every pin and the door flies, loot rains into the bag, the next vault opens. One level = one vault, and the vault index is persistent, so the door art (rust → steel → copper → gold → gem-set) is a real career, not a per-run reset.

Behavioral systems (variable-ratio jackpots, three-strike alarm with a rewarded "Bribe the Cops", unfinished hideout shelf, DDA flow bend) stay first-class nodes.

Open `project.godot` in Godot 4.6, press Play. Click / tap / space when the pick is in the green gate.

---

## 1. Scene tree and files

```
Main.tscn                          boot composition
├── GameWorld.tscn                 dial, input, DDA, VR, juice
│   ├── Camera2D
│   ├── Arena (RingArena.gd)       vault door + dial, gate windows, door-seam crack light
│   │   ├── LockPin                tumbler: seat bounce, eject on miss
│   │   ├── Pointer (RingPointer)  rotated pick + direction chevron, hit_flash
│   │   └── Burst (GPUParticles2D)
│   ├── InputProcessor             one verb: press = lock
│   ├── MetaUpgrade                Crew (offline stash) + Pro Gloves economy
│   └── Juice                      hitstop / shake / punch / alarm lamps / loot rain / haptics
├── UIManager.tscn
│   ├── HUD                        VAULT N · alarm lamps · grade word · loot bag · Market / Stash
│   ├── Card                       end-of-vault: CRACKED / BUSTED, loot roll, hideout ring, 3x ad
│   ├── RevivePopup.tscn           third strike → Bribe the Cops (rewarded) or Get Caught
│   ├── SettingsPopup.tscn         language / sound / vibration (+ Auto-Crack if purchased)
│   ├── MarketPopup.tscn           Crew, Pro Gloves, dial skins; hideout shelf count
│   └── ClaimPopup.tscn            Crew stash collect
├── SoundManager.tscn              procedural tones
└── AdsManager.tscn                mock rewarded mediation

Autoloads: EventBus, Settings, GameState, TimeScale (sole writer of Engine.time_scale), OverlayPause
```

| Path | Role |
|---|---|
| `scripts/autoload/GameState.gd` | Persistent vault index, single currency (cash), alarm strikes, stage curve (pins / rpm / windows), vault types, hideout loot list, save migration |
| `scripts/world/GameWorld.gd` | Level loop: spin → tap → grade → pin → crack → card. Strikes, bribe, 3x boost |
| `scripts/core/TimingEngine.gd` | Angle delta → Perfect / Good / Near-Miss / Miss, plus per-hit pitch and haptic profile |
| `scripts/behavioral/DynamicDifficulty.gd` | Flow-channel tuner; bends the stage curve ±15% |
| `scripts/behavioral/VariableRatioSchedule.gd` | Skinner VR payouts / jackpots |
| `scripts/behavioral/ZeigarnikTracker.gd` | Needle-passed-the-pin tension + loot shelf tease |
| `scripts/meta/MetaUpgrade.gd` | Crew (offline cash), Pro Gloves (wider Perfect + bigger bursts), prices |
| `scripts/ui/UIManager.gd` | HUD + end-of-vault card |
| `scripts/ui/LootBag.gd` | Duffel bag: rolling cash number, gold fill, bounce on loot |
| `scripts/ui/AlarmLamps.gd` | Three wall lamps, no text |
| `scripts/ui/QuestRing.gd` | Unfinished ring for the next hideout item (card only) |
| `scripts/ui/RevivePopup.gd` | Bribe the Cops |
| `scripts/vfx/VaultSprites.gd` | Painted door per vault, tumbler, tap hand, gold bar, gem |
| `translations/strings.csv` | EN / TR strings |

Portrait canvas: **720×1280**, `canvas_items` stretch, mouse-emulated touch.

**Localization.** Every player-facing string is a key in `translations/strings.csv`. Code-set texts go through `tr()` and re-render on `NOTIFICATION_TRANSLATION_CHANGED`. Do not call `to_upper()` on translated text (Turkish `i` → `İ`); write uppercase into the CSV instead.

---

## 2. Level structure (one vault = one level)

- `GameState.current_stage = stages_cleared + 1` on every `reset_run()`. A bust retries the same vault; a crack moves on. Nothing resets to vault 1.
- **Pins per vault** (`GameState.pins_for`): 3 for vaults 1–2, 4 for 3–5, 5 for 6–10, 6 for 11–25, 7 for 26–50, 8 from 51. Every 5th vault is a **Golden Vault**: +3 pins (cap 10), 2× loot, gold door, gold accent ring.
- **Dial speed** (`base_rpm`): 0.38 rps → 0.55 @10 → 0.75 @25 → 0.9 @60. **Good window** (`base_good_deg`): 20° → 16° @10 → 13° @25 → 11° @60. Perfect = 42% of Good (Pro Gloves widen it +6%/level); Near-Miss band = Good + 5°.
- **Direction flips** start at vault 3 (`flips_enabled`). The bezel flash telegraphs them.
- **DDA** no longer owns the numbers. It bends rpm and windows by at most ±15% around the stage curve (`GameWorld.DDA_BAND`), targeting ~72% Good-or-better.
- **Vault types** by first index: 1 Piggy Bank, 3 Office Safe, 6 Bank Vault, 11 Museum, 26 Casino, 51 Fort Knox. Shown on the card and as the accent ring.

Target level length: 20–40 s.

---

## 3. Forgiveness, alarm, and the bribe

| Event | What happens |
|---|---|
| Miss / Near-Miss | Alarm +1 (lamp lights, short red flash, pin ejects, dial jams ±3° for 200 ms). Seated pins are kept. The same vault keeps spinning. |
| Third strike | Full police strobe + siren. `revive_offered` → **Bribe the Cops** (rewarded ad). Always offered once per vault; no record gating. |
| Bribe taken | Alarm resets, 3-2-1 countdown, same vault continues with its seated pins. |
| Bribe skipped | `run_ended("caught")` → BUSTED card → Try Again on the same vault. |

Near-Miss keeps the heavier 180 ms hitstop so the almost-win still lands harder than the win.

---

## 4. Loot, meta, and retention

- **Single currency: cash ($).** Each seated pin drops a little; the vault pays `40 + 12 × vault` on the last pin (×2 on golden). v1 saves fold `energy + coins` into cash.
- **Loot bag** at the bottom of the screen shows cash as a rolling number and a gold fill relative to the cheapest upgrade. Door open → loot particles burst with heavy gravity toward the bag → bag bounces 1.14× half a second later.
- **End-of-vault card**: `VAULT N CRACKED` + vault type, loot rolls up over 0.7 s, hideout ring for the next item, `NEXT VAULT`, `3x LOOT` (rewarded), Market. One tap anywhere continues.
- **Hideout shelf**: 12 loot items (`GameState.LOOT_ITEMS`), one every 3 cracked vaults. The card shows the unfinished ring (teased at 82%) or `NEW LOOT: …`.
- **Market**: Crew (offline cash, +25%/level), Pro Gloves (+12% Perfect power and +6% Perfect window per level), dial skins ($200 / $600).
- **Crew stash**: offline earnings (0.67/s × Crew, 8 h cap) wait in `unclaimed_cash` and surface as a HUD chip and the Claim popup.
- **Auto-Crack** is IAP-only now. The old "first ring unlocks Auto-Tap" reward is gone.

---

## 5. Juice (what fires on what)

- Perfect: 60 ms hitstop → 7 px shake → zoom 1.05 → dial bounce 1.08 → gold burst → pin flash → glow pulse. Pin seat bounce 1.0 → 1.3 → 1.0 in 120 ms. Door-seam crack light grows with `pins / needed`.
- Good: same chain without hitstop, smaller numbers.
- Near-Miss: 180 ms hitstop, 14 px shake, siren pitch sliding 1.0 → 0.7 over 400 ms.
- Miss: 18 px shake, dial jam, pin eject, low clunk.
- Door open: 100 ms freeze → camera punch → door flies → rust flakes / shell chips → gold + gem rain and burst → "ka-chunk" then "cha-ching" 200 ms later → bag bounce.
- Alarm lamps: strike N = N short red flashes; strike 3 = full strobe.
- Combo label appears from x3 with a 1.3 → 1.0 pop.

Guidelines for production art:

1. One dark field (`#0B1020`), one accent (green gate), one danger (red), one loot (gold).
2. Hit feedback is **time** (hitstop) before **particles**.
3. Near-miss uses *longer* hitstop than Perfect.
4. Golden vault is the only time the whole dial may go gold.
5. Keep GPUParticles `one_shot` + `explosiveness = 1`.

---

## 6. Monetization (mock)

| Placement | Trigger | Reward |
|---|---|---|
| `near_miss_revive` | Third alarm strike | Bribe the Cops: alarm reset, vault continues |
| `end_multiplier` | Card `3x LOOT` | Twice the vault's banked cash again |
| IAP `no_ads_bundle` | Shop | Skip non-revive ads, 3x auto-claimed |
| IAP `auto_tap` | Shop | Auto-Crack: crew taps the Good window |
| IAP `dial_obsidian` | Shop | Cosmetic dial |

`AdsManager` waits `mock_latency_ms` then emits `ad_finished`. Replace `show_rewarded` with AdMob / LevelPlay; keep the EventBus contract.

---

## Retention mapping (design hypotheses)

| Lever | System |
|---|---|
| D1 | Persistent vault number + unfinished hideout ring on the card |
| Session length | 20–40 s vaults, one-tap continue, golden vault every 5th |
| D7 | Door art career (rust → gems), crew stash drip, 12-item shelf |

Instrument `EventBus.tap_evaluated` / `run_ended` / `revive_resolved` before claiming numbers.

---

## Next production steps

1. Swap mock ads for a mediation SDK and store IAP receipts.
2. Hideout screen: draw the 12 shelf items instead of naming them.
3. Glove / hand skins on the dial (the coach hand is the only hand today).
4. Telemetry: grade histogram, bribe conversion, time-to-second-session.
5. Android export: portrait, immersive, texture compression already flagged in `project.godot`.
