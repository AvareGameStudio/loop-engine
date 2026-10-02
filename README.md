# Loop Engine

Hybrid-casual **one-tap** prototype for Godot **4.6**. Core loop is precision timing on a rotating ring; meta loop is idle energy + upgrades. Behavioral systems (variable-ratio rewards, near-miss loss aversion, Zeigarnik unfinished bars, DDA flow) are first-class nodes, not afterthoughts.

Open `project.godot` in Godot 4.6, press Play. Click / tap / space when the pointer sits in the gold arc. Hold slightly longer to dip into slow-mo assist; it drains the gold Focus bar, which Perfects refill.

---

## 1. Scene tree and files

```
Main.tscn                          boot composition
├── GameWorld.tscn                 ring, input, DDA, VR, juice
│   ├── Camera2D
│   ├── Arena (RingArena.gd)       static ring / windows (redraws on change only)
│   │   ├── Glow                   ring_glow shader, jackpot pulse
│   │   ├── Pointer (RingPointer)  rotated pointer + direction chevron, hit_flash
│   │   └── Burst (GPUParticles2D)
│   ├── InputProcessor
│   ├── IdleTick                   offline-style energy drip
│   └── Juice                      hitstop / shake / punch
├── UIManager.tscn
│   ├── HUD                        score, combo, stage bar
│   ├── Meta                       Zeigarnik loops + upgrades
│   ├── RunOver                    end-of-run + 3x rewarded
│   └── RevivePopup.tscn           near-miss second chance
├── SoundManager.tscn              procedural tones
└── AdsManager.tscn                mock rewarded mediation

Autoloads: EventBus, GameState, TimeScale (sole writer of Engine.time_scale)
```

| Path | Role |
|---|---|
| `scripts/core/TimingEngine.gd` | Angle delta → Perfect / Good / Near-Miss / Miss |
| `scripts/core/InputProcessor.gd` | One-tap + hold-and-release, Focus meter |
| `scripts/autoload/TimeScale.gd` | Hitstop + slow-mo arbitration |
| `scripts/world/RingPointer.gd` | Pointer, direction telegraph, flash |
| `scripts/behavioral/VariableRatioSchedule.gd` | Skinner VR payouts / jackpots |
| `scripts/behavioral/DynamicDifficulty.gd` | Flow-channel RPM + windows |
| `scripts/behavioral/ZeigarnikTracker.gd` | Unfinished ~82% meta bars |
| `scripts/monetization/AdsManager.gd` | Mock rewarded placements |
| `scripts/monetization/IAPCatalog.gd` | No-Ads, Auto-Tap, cosmetics |
| `shaders/ring_glow.gdshader` | Additive ring glow on jackpot |
| `shaders/hit_flash.gdshader` | Pointer flash on perfects |

Portrait canvas: **720×1280**, `canvas_items` stretch, mouse-emulated touch.

---

## 2. Core timing engine

`TimingEngine.evaluate(pointer, target)` uses `angle_difference` so wrap-around at 0° is correct.

| Grade | Default window | Intent |
|---|---|---|
| Perfect | ≤ 7° | Dopamine spike, extra score 1.35× |
| Good | ≤ 16° | Keep the run alive |
| Near-Miss | Good + 1–3% of the circle (~3.6–10.8°) | Loss aversion / revive |
| Miss | Outside near | Hard fail |

Result payload includes `delta_deg`, `full_circle_pct`, `accuracy`, and `in_loss_aversion_band` so UI and ads never re-derive policy.

Input: short press = tap lock. Hold past 120ms = slow-mo, release commits. Auto-Tap IAP locks only inside the Good window and goes through the same grading path; it never feeds DDA. Input is disarmed during the respawn delay, and a revive resumes after a 3-2-1 countdown.

---

## 3. Behavioral systems

**Variable ratio (Skinner)**  
Successes decrement a random interval in `[3, 9]`. On fire, a weighted table returns x2–x8 or a jackpot (12–25×, extra 8% override). Nothing is on a fixed “every 5th hit.” `peek_tension()` can tease the HUD without revealing the counter.

**DDA / Flow (Csikszentmihalyi)**  
Rolling 12-hit window. Target ~72% Good-or-better and ~28% Perfect. High success raises RPM and tightens Perfect; high error lowers RPM and opens the window. Near-miss band stays a 1–3% ring *beyond* Good so Prospect Theory does not collide with the success window.

**Zeigarnik**  
`ZeigarnikTracker.loops()` caps visible fill at **0.82** unless a loop is actually complete. Generator, global multiplier, current ring, and theme collection all persist via `user://loop_engine_save.json`. Run-over copy names how many loops are still open.

**Near-miss (Kahneman / loss aversion)**  
Grade → 180ms hitstop → “SO CLOSE!” with exact degrees/% → Rewarded **Second Chance**. One revive per run. Skip ends the run so the almost-win is not cheap.

---

## 4. Monetization (mock)

| Placement | Trigger | Reward |
|---|---|---|
| `near_miss_revive` | Near-miss popup | Continue run |
| `end_multiplier` | Run-over 3× | Extra energy/coins |
| IAP `no_ads_bundle` | Shop | Skip non-revive ads |
| IAP `auto_tap` | Shop button in prototype | Idle lock cadence |
| IAP cosmetics | Catalog | Trails only (no P2W) |

`AdsManager` waits `mock_latency_ms` then emits `ad_finished`. Replace `show_rewarded` with AdMob / LevelPlay; keep the EventBus contract.

---

## 5. Visual polish (low budget)

Already wired:

- GPU particle burst on grade / jackpot
- Camera shake + zoom punch (`Juice.gd`)
- Hitstop via `Engine.time_scale`
- Grade label overshoot tween
- Revive panel `TRANS_BACK` pop
- Additive shaders for glow / flash

Guidelines for production art:

1. One dark field (`#0B1020`), one accent (cyan), one danger (magenta), one jackpot (gold). No extra hues.
2. Hit feedback is **time** (hitstop) before **particles**. Particles without hitstop feel cheap; hitstop without particles feels broken.
3. Near-miss uses *longer* hitstop than Perfect. The almost-win must feel heavier than the win.
4. Meta bars never sit at 100% on exit unless the player collected. Leave the loop visibly bitten.
5. Jackpot is the only time the whole ring may go gold. Scarcity protects the VR schedule.
6. Keep GPUParticles `one_shot` + `explosiveness = 1`. Looped emitters kill the “snap” of a tap game.
7. Screen shake amplitude: Perfect 7px, Near-miss 14px, Miss 18px. Miss should feel like a slap, not a flourish.

---

## Retention mapping (design targets)

| Metric lever | System |
|---|---|
| D1 session 2 | Near-miss replay + save of ~82% generator bar |
| Session length | VR jackpots + stage rings that reset the target angle |
| D7 | Persistent DDA seed + unfinished collection loop + idle energy drip |

These are **design hypotheses**, not live telemetry. Instrument `EventBus.tap_evaluated` / `run_ended` / `revive_resolved` before claiming D1 > 50% / D7 > 20%.

---

## Next production steps

1. Swap mock ads for a mediation SDK and store IAP receipts.
2. Add a second ring theme (Aurora unlocks at stage 3 in code).
3. Telemetry: grade histogram, revive conversion, time-to-second-session.
4. Android export: portrait, immersive, texture compression already flagged in `project.godot`.
