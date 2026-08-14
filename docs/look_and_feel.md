# AGES: graphics and game feel (researched 2026-08-08)

The world reads flat and cheap, and interactions land with no weight. Both are fixable with
known techniques. Ordered by return on effort.

## THE 2025 LIGHTING RESET — read this before any lighting tutorial

**`Lighting.Technology` is dead.** Unified Lighting went fully live with automatic migration on
**2025-07-23**. Voxel/ShadowMap/Future are replaced by two properties, **neither of which is
scriptable**:

- **`LightingStyle`** — `Realistic` (detailed shadows/shading/specular) or `Soft` (flatter,
  diffused, "classic Roblox").
- **`PrioritizeLightingQuality`** — `Enabled` keeps lighting quality and degrades draw distance
  first; `Disabled` sacrifices lighting first.

Migration map: Future → `Realistic` + `Enabled`; ShadowMap → `Soft` + `Enabled`; Voxel → `Soft`
+ `Disabled`. **Every tutorial older than mid-2025 telling you to "set Technology to Future" is
outdated.**

**For AGES: `LightingStyle = Realistic`, `PrioritizeLightingQuality = Disabled`** — good shading
model, but the engine protects draw distance and framerate on phones, which matters more in an
open world. `ShadowSoftness` (0.2–0.5 usable) is only valid under `Realistic`.

**The PBR interaction that fixes "washed out":** set `EnvironmentSpecularScale` and
`EnvironmentDiffuseScale` to **1** and `Ambient`/`OutdoorAmbient` toward **(0,0,0)** so the
environment probe supplies fill. Amateur games do the opposite — grey ambient with low scales —
and that is exactly the flat look we have. **Metals are invisible without
`EnvironmentSpecularScale`.**

**Hidden flatness culprit:** `ColorGradingEffect.TonemapperPreset` has `Default` (vivid) and
`Retro` (pre-2019 emulation, desaturated, low contrast). If a `ColorGradingEffect` is sitting in
Lighting on `Retro`, that alone washes everything out. **Check for this first.**

`ExposureCompensation` (−5..5, default 0) is the best "make it filmic" knob — ±0.3 for mood.

## Atmosphere is the highest-ROI object in the engine

It gives **aerial perspective** — distant objects desaturate and shift toward sky colour — which
is the strongest depth cue the human eye uses. **A flat world is usually a world with no
Atmosphere.**

Order matters: **`Glare` and `Decay` do nothing unless `Haze > 0`.** Set Haze, then Glare, then
Decay. Official Core Curriculum values: `Density` **0.375**, `Offset` **0.17**. Outdoor natural
Density 0.3–0.5; fog/rain ~0.8. Decay 0.8–1.0 natural, Glare 0.3 subtle. `Color` should match
the skybox horizon band — **Atmosphere pulls character from the sky, so a cheap skybox caps your
ceiling**. Use a skybox with a **darker lower hemisphere**, or every reflective surface looks
wrong (the probe samples it).

`Clouds` **must be parented to `Terrain`**, not Workspace, or it silently fails to render.
`Cover` 0.4–0.6 = fair weather.

**Day/night done properly:** don't just step `ClockTime`. Drive a whole keyframed grade off
normalised time — `Ambient`, `OutdoorAmbient`, `Atmosphere.Color`, `Atmosphere.Density`,
`ColorCorrection.TintColor`, `Bloom.Intensity`, `Clouds.Color` all lerped between authored
dawn/day/dusk/night presets. Run it **client-side** off a server-replicated time value; lighting
is client-rendered anyway and replicating `ClockTime` every 0.1s is wasted bandwidth.

## Post-processing — restraint is the whole skill

Baseline grade:
```
ColorCorrection: Brightness 0, Contrast 0.10–0.20, Saturation 0.05–0.15, TintColor barely-there
Bloom:           Intensity 0.6–0.9, Threshold 1.5–2.0, Size 24
SunRays:         Intensity 0.10–0.20, Spread 0.8–1.0
DepthOfField:    subtle FarIntensity only; NOT in third-person gameplay
```
- **Bloom Threshold is the real control, not Intensity.** Low threshold = everything glows =
  washed. If bloom eats into building or character silhouettes, you're over.
- `ColorCorrectionEffect` **clips highlights** — it is not filmic grading. Do mood with
  `ExposureCompensation` + Atmosphere instead.
- **Multiple ColorCorrections compose multiplicatively.** Exactly one persistent base grade in
  `Lighting`; put temporary per-player grades (indoor tint, sleep transition) on the **Camera** —
  effects under `Lighting` show to everyone, under `Camera` only to that client.
- **Never `Blur` the whole screen during gameplay** — menu backdrops only. It's a mobile
  fill-rate killer.
- ColorCorrection `Brightness` is a trap: +0.5 already looks washed. Keep 0 to ±0.1.

**Palette for a life sim:** warm, slightly desaturated, high midtone contrast reads as
"cozy/lived-in." The most common flat-world failure is every part being a different unrelated
hue at full saturation. **Desaturate the base environment hard, then let gameplay-critical
objects be the only saturated things on screen** — readability and expense at the same time.

## Materials

`SurfaceAppearance` is **MeshPart-only** and **not scriptable at runtime**. `ColorMap` is
**albedo, not diffuse** — no baked lighting or AO; baked shading fighting real lighting is a
classic amateur tell. `NormalMap` is **tangent space only**. **Skipping RoughnessMap and
MetalnessMap is the #1 reason custom Roblox surfaces look like printed plastic** — roughness
variation (wear, fingerprints, pooling) is what makes a surface read as real.

Texel density: 5×5 studs → 256²; 10×10 → 512²; 20×20 → 1024². **Downsize non-colour maps to
256²** for near-zero loss. **Tint-reuse one ColorMap** across many objects (tinting is free).
**Tile, don't stretch** — blurry custom textures are almost always a non-tiling map stretched
over a large face, not a resolution problem. Audit via Dev Console → Memory → GraphicsTexture.

**`MaterialService` + MaterialVariants is our highest-leverage material move**: override the
default `Enum.Material` set globally with PBR variants and an entire town of plain `Plastic`
parts upgrades at once, with no geometry rebuilt.

## What makes a Roblox game look expensive

1. **Density and set dressing, not fidelity.** A flat world is an *empty* world. Bins, signage,
   cables, planters, parked bikes, litter, awnings. **Silhouette variety at the horizon is what
   the eye grades.**
2. **Modular kits with per-instance variation** — fixed grid, then vary by tint + material +
   prop dressing. Break repetition on large tiling surfaces.
3. **Trim sheets** — one atlas of edge/panel/detail strips UV'd across a whole kit. One draw
   call, infinite variation, no stretching.
4. **Greebles at three scales** — building silhouette, mid-scale props, small detail. **Missing
   the mid scale is what makes worlds feel like architectural models.**
5. **Lighting-led composition** — rim light on building edges, warm pools spilling from windows
   and doorways, dark negative space between. Uniform brightness = flat.
6. **Cohesion beats fidelity.** Roblox's 2025 Innovation Award for Best Creative Direction went
   to *Steal a Brainrot* — stylised, not realistic. Consistent intent wins.

## Performance budgets

Target **< 1,000 draw calls** and **< 1,000,000 triangles** on the baseline device;
**< 5,000 Workspace instances** during active play for safe mid-range mobile. Mobile particles
150–300 active vs 500–800 desktop.

Reuse the same `MeshId` + `TextureId` pair everywhere — identical pairs batch into single draw
calls. Prefer MeshParts over Unions. **`CollisionFidelity = Box` on every small anchored
decorative part**; audit by filtering Explorer on `PreciseConvexDecomposition`. `CastShadow =
false` on small/distant props. `RenderFidelity` never `Precise` on background props.

Streaming: `StreamingIntegrityMode = PauseOutsideLoadedArea`, `StreamOutBehavior =
Opportunistic`, leave Min at 64 and Target at 1024 (the *gap* is the network buffer; equal
values cause pauses). Stress-test at `StreamingTargetRadius = 64` — streaming bugs only manifest
at small radii. Debug overlay **Shift+Ctrl+F3**. `Model.LevelOfDetail` imposters **have no
textures** and only look acceptable at 1024+ studs. Enable **`Workspace.EnableSLIMAvatars`** —
directly relevant to a town full of NPCs.

Ship three quality tiers gated on `UserGameSettings.SavedQualityLevel`: particle rate, extra
emitters, ambient NPC count, WindShake, DepthOfField, SunRays.

## Camera

**One `RenderStepped` pipeline:** `FOV = base + Σ additive springs`, `CFrame = base * offsetSpring
* shakeOffset`.

- **Never tween FOV per keypress** — spamming sprint spawns competing tweens and the camera
  fights itself. Drive toward a target with a per-frame lerp/spring; inherently interrupt-safe.
- **Drive FOV from velocity, not a boolean.** 70 base → 78 sprint is a good third-person band.
- **Camera lag is itself juice** — Nijman's point is that lerp makes the camera behave like a
  physical object with inertia. Snapping feels cheap; trailing ~80–120ms feels weighty.
- Shake: `Shake` from RbxUtil, bound at `RenderPriority.Camera.Value + 1`. **Gotcha:** if you
  don't own the camera CFrame, the default camera scripts feed back on the shaken CFrame and
  escalate. Store base, apply shake for render, restore on Heartbeat.
- Spring modules operate on Vector3 — run **separate springs for position and rotation** and
  compose.
- **Make shake intensity a player setting** — motion-sickness trigger, and 13+ audiences report it.

---

# GAME FEEL

## The canonical checklist

Nijman's *The Art of Screenshake* iteration order, which is a ready-made list: baseline →
animation → faster resolution → bigger effects → muzzle flash → impact effects → hit reaction →
knockback → **permanence** → camera lerp → screenshake → **hit pause** → recoil.

Categories: **anticipation → impact → reaction → permanence → camera.** **"Permanence" is the
most-skipped and the most on-theme for a life sim**: what you did stays visible. The dirty dish
still on the table, the toy on the floor, the grade taped to the fridge. Every action should
leave a trace you can walk back to.

**The constraint (Kao, CHI 2024):** both none *and extreme* juiciness significantly decrease
player experience — over-juice makes it impossible to tell which feedback is mechanically
meaningful. Amplified feedback creates a sense of competence **only when attached to an action
that displays skill**. Juice choices hard; leave ambient events quiet.

**"Oil" before "juice."** Oil = smoothness (latency, coyote time, input buffering, corner
correction). Juice = feedback amplification. **Juice cannot rescue an unresponsive core.**

## Easing — the curves that matter

Of 11 `EasingStyle` values you almost only need:
- **`Back` + `Out`** — arrive with overshoot. The pop. Panels, rewards, confirmations.
- **`Back` + `In`** — anticipate then leave. Dismissals.
- **`Quint` + `Out`** — front-loads nearly all motion; the snappy-menu curve.
- **`Sine`** — ambient/idle only, never feedback. **`Linear`** — progress bars only.
- **`Elastic`/`Bounce`** — almost always too noisy (`Back` exists because Elastic is too much).

**Durations 0.15–0.35s. Most unjuicy Roblox UI is correct curves played too slowly.** Exits
faster than entrances (~0.15s) — never make a player wait to dismiss.

**Standardise three curves game-wide:** `Back.Out` 0.22s (enter/succeed), `Quad.In` 0.14s
(exit), `Quint.Out` 0.3s (transitions). Consistency reads as intentional design.

**Scale punch:** `AnchorPoint = (0.5, 0.5)` so it scales from centre, then 1.0 → 1.15 in 0.08s →
1.0 in 0.12s with `Back.Out`.

**Hit-stop:** Roblox has **no global time scale** — hand-roll it. `AnimationTrack:AdjustSpeed(0)`,
zero WalkSpeed, hold **0.05–0.15s**, restore via `task.delay`.

## Particles that don't look cheap

**Good VFX is multiple simple emitters composed, never one complex emitter.**
- Kill the defaults (white stars, Rate 20).
- **Never leave `Size`/`Transparency` as flat lines** — author `NumberSequence` curves.
  Transparency must end at 1.
- **Use the `envelope` on sequence keypoints.** That randomisation is literally the
  cheap→expensive switch; it stops particles looking like clones.
- **`Squash`** does non-uniform scaling over lifetime — streaked sparks, flattened shockwave
  rings instead of blobs.
- **Author textures greyscale** so `ColorSequence` drives all tinting.
- **Parent emitters to `Attachment`s, not BaseParts** — BaseParts spawn particles randomly
  through the whole bounding volume (mushy); Attachments spawn from a point.
- **`FlipbookStartRandom = true` with `FlipbookFramerate = 0`** — every particle becomes a random
  static frame. Free variety from one emitter.
- `VelocityInheritance` non-zero so trails don't feel detached. Avoid legacy `Fire`/`Smoke`.

## Haptics — new, and almost nobody uses it

`HapticService` is **deprecated**. Use the **`HapticEffect` Instance** (May 2025):
```lua
local fx = Instance.new("HapticEffect")
fx.Type = Enum.HapticEffectType.UIClick
fx.Parent = workspace
fx:Play()
```
Works on Android and iOS phones, PlayStation/Xbox pads, Quest Touch. Presets are per-device
optimised. `SetWaveformKeys` for custom (keep under 1s; destroy looped effects). **This is a
free differentiator for a touch-first life sim.** Ship an intensity setting.

## Feedback timing — the fix for "interactions feel dead"

| Window | Meaning |
|---|---|
| **0–50 ms** | Acknowledge input here. Target click-to-photon < 50ms |
| ~15–30 ms | Where latency becomes consciously noticeable at all |
| ~50–60 ms | "Something feels wrong" begins |
| ~100 ms | Visibly degraded, obvious lag |
| ~200–250 ms | Human visual reaction time — the scale |

**The operational rule: acknowledge immediately even if you resolve late.** Play the press
animation and click sound on the client, on input, *before* the server round-trip, then
reconcile. **A refusal that arrives 200ms later still feels responsive if the button reacted at
20ms.** This is directly applicable to our 3-dot prompts and ChoicePanel, which currently wait
on the server.

Latency doesn't just hurt motor control — the CHI PLAY 2023 study found it significantly reduces
perceived *mastery, progress feedback, immersion, autonomy and enjoyment*.

**Multi-channel rule: every meaningful action fires ≥3 channels.** For a 3-dot prompt: dot
scale-pops + UI click sound + `HapticEffect.UIClick` + character head-turn/hand-reach + result
popup.

**Distinguish success from failure by channel, not just colour.** Success = rising pitch +
upward motion + `Back.Out`. Failure = falling pitch + short horizontal shake + `Quad.In`.
Colour-only fails for colourblind players and reads as ambiguous at speed.

Also cheat toward the player: coyote time, input buffering, generous interaction hitboxes.
Nobody notices; everybody feels it.

## Sound — the cheapest massive upgrade

**Sourcing:** Toolbox → Creator Store → Audio has **100,000+** professionally-produced SFX from
Roblox's Pro Sound Effects partnership (official uploads end in `(SFX)`). Community creators can
publish free public SFX **under 10 seconds**. Audio uploads are free with monthly caps.

- **Pitch randomisation** — `Sound.PlaybackSpeed = base * math.random(95,105)/100`. **One line,
  and it instantly removes the machine-gun repetition that screams amateur.**
- **Sample pools** — 3–5 variations per event. Footsteps: 4–8 per material, emitter parented to
  the **foot Motor6D**, not the HumanoidRootPart, with material-aware selection.
- **Layering** — every impact is anticipation (whoosh) + impact (transient) + reaction. Only play
  the impact if it connects.
- **SoundGroups** as mixer *and* voice management: one per category (Music, SFX, UI, Ambience),
  cap concurrent sounds per group, stop the oldest. **Volume is multiplicative** — rarely go
  above 2.
- **RollOff `InverseTapered`** avoids the sudden pop of `Inverse`.
- **Ambience beds: never one loop.** Layer 3+ (wind + birds + distant traffic + insects) at
  different RollOff radii, cross-faded by zone **and by `ClockTime`**. This is what makes a town
  feel alive.
- **UI conventions:** hover = quiet tick; press = click with low-end body; confirm = rising
  two-note; cancel = single falling note; error = short dull thud, never a harsh buzz; reward =
  layered chime + shimmer tail. All under 200ms except rewards.

## UI scaling and type

- **Never position/size with Offset.** But pure Scale isn't sufficient either — a scale-sized
  square is only square on a square screen. **`UIAspectRatioConstraint` belongs on every element
  whose shape carries meaning** (portraits, slots, icons, the 3-dot prompt).
- **Don't mix Scale and Offset on the same axis** unless a constraint pins the result.
- `UISizeConstraint` to clamp; `UIScale` to ship a global UI-scale player setting.
- `ScreenGui.ScreenInsets = CoreUISafeInsets` (default) keeps clear of the topbar and notches.
  Setting `IgnoreGuiInset = true` while on `CoreUISafeInsets` **silently flips you to
  `DeviceSafeInsets`**. Defaults shifted in engine version 726 — verify rather than trusting old
  tutorials.
- **`TextScaled` is a trap** — it shrinks text to unreadable on mobile. Use fixed `TextSize`
  14–18 for body plus `AutomaticSize` containers.
- Use **`FontFace`** (`Font.fromName`), not the legacy `Font` enum. Build a typography
  ModuleScript with named styles and apply by tag; never hardcode font properties in UI scripts.
  Roblox **ignores variable-font weight axes** — export static weights.
- Motion: **staggered reveals** (children enter at 30–50ms offsets, not simultaneously);
  number popups that scale-pop then drift and fade; counters that **tick** rather than snap.

## A world that moves on its own

The strongest production-value signal, and mostly cheap:
- **`WindShake`** (boatbomber) — 77,750 leaf meshes at 220+ FPS via `BulkMoveTo`. **Do not shake
  collidable objects** — the physics cost is what kills you.
- **Walking NPCs (we have these):** `PathfindingService` controls *where*, animation controls
  *how*. **Without animation, NPCs slide in a stiff pose — the single loudest amateur tell.**
  Give them a walk cycle, an idle, and **randomised `WalkSpeed` (±15%)** so the crowd doesn't
  move in lockstep. Waypoint graphs for sidewalks beat per-NPC A*.
- **Idle variation** — weighted pool (breathe / look around / check phone / shift weight) every
  4–10s randomised. Costs one animation table.
- **Procedural head-turning** — Motor6D `Neck.C0` lerped toward the nearest interesting target.
  **~15 lines, and the single biggest "these things are alive" upgrade.**
- Ambient layer: birds, distant traffic, flickering signage, steam vents, drifting leaves. Gate
  on quality tier.

## If you only do ten things

**Graphics:** (1) set the lighting foundation once — `Realistic` + `Disabled`, Atmosphere at
0.375/0.17 with Haze before Glare/Decay, Clouds inside Terrain, Environment scales to 1, ambient
tinted not grey, and verify no `Retro` tonemapper. (2) MaterialVariants globally via
MaterialService. (3) One subtle grade, not five loud ones. (4) Set dress at three scales.
(5) Fix the camera pipeline — one loop, velocity-driven FOV, positional lag, shake module.

**Feel:** (6) Sound on every state change with pitch randomisation and sample pools.
(7) Client-side acknowledgement inside 50ms on every interaction, before any round-trip.
(8) Standardise three easing curves and three durations game-wide. (9) Make the world move on
its own — WindShake, animated NPCs with varied speed, head-turn, idle variation, ambience beds.
(10) Add **permanence** — consequences stay visible in the world.
