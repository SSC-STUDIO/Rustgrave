# Rustgrave — Architecture Quick Map

Target: **Godot 4.7** · GDScript only · zero external deps.

显示边界：世界始终在 **640×360 SubViewport** 中以原生像素渲染，`GameCamera.zoom=1`；`GamePresentation` 将世界图像和 1280×720 设计单位的 UI 一起放入最大整数倍率内容矩形。`PresentationMetrics` 是内容矩形、倍率和坐标转换的唯一来源，非 16:9 窗口只增加黑边。

世界图像经过 `assets/shaders/pixel_smooth.gdshader`（3x 用 Scale3x，其余倍率用 Scale2x/EPX）：只把对比色块之间的斜向台阶圆滑掉，平面、渐变和 1px 细节原样通过，所以 1080p/1440p 上不再是马赛克但仍是像素画。`GamePresentation.pixel_smoothing` 是会话级开关，暂停菜单「像素平滑」可关；`scale_hint` 随窗口整数倍率更新。

## Autoloads

Do not give autoload scripts a `class_name` — the autoload name is the API.

| Autoload | Script | Role |
|---|---|---|
| `GameEvents` | `scripts/autoload/game_events.gd` | Signal bus (`hit`, `parried`, `announcement`, `toxin_changed`, `core_acquired`, `ability_unlocked`, `ending_chosen`, …). Cross-cutting traffic goes through it; systems do not couple directly. |
| `Juice` | `scripts/autoload/juice.gd` | Hit-stop / camera punch. |
| `Sfx` | `scripts/autoload/sfx.gd` | One-shot library + looping rain / rust-rain / cemetery drone. `Sfx` / `Ambience` buses. |
| `Fx` | `scripts/autoload/fx.gd` | Particles, ember attach, death puffs. |
| `SaveData` | `scripts/autoload/save_data.gd` | `user://` save: player, inventory, persistent world, consumed paths, story `flags`, ending. |
| `Director` | `scripts/autoload/director.gd` | Fade, sequenced cutscenes, cinematic letterbox. Never touches `Engine.time_scale`. |
| `WorldClock` | `scripts/autoload/world_clock.gd` | Simulation only: `time_of_day`（20 分钟一昼夜）、`phase`、`weather`（haze / rain / fog / ember_wind / rust_rain / **clear**，每 50–110s 随机切换并按阶段加权）、`zone`、`wind_*`（风向 36–72s 随机翻转、阵风起伏）。API：`wind_vector()` `sway_radians()` `mood_tint()` `outdoor_tint()` `indoor_tint()` `cloud_alpha()` `ground_fog_alpha()` `fog_veil_alpha()` `wind_mote_density()` `nest_light_*()` `outdoor_moon_energy()` `indoor_fill_energy()`。不创建 Sprite / Light。演出层是 `WorldAtmosphere` / `WindSway` / `WindFx` / `CineFx` / `WeatherFx` / `WorldLight`。 |

## Level01 (`scenes/levels/Level01_Static.tscn`)

The `.tscn` stays the authored map (platforms, props, three parallax plates). `level01_static.gd` only spawns player / camera / HUD, wires plate→door, and plants grave sprites. Runtime children do the rest so `Platforms/`, `Props/ForgeHeart`, and `BossGate` paths do not move:

| Script | Role |
|---|---|
| `scripts/levels/level01_env.gd` | Shared `plant()` — foliage sits on a foot pivot with `WindSway`; play-layer trees also get a sibling `LeafShed`. |
| `level01_static.gd` waymarks | 1x `waymark_sign.png` plank on a post; the label is a 12px pixel-font `Label` sized to the plank face (`SIGN_PLANK`), so the word is written on the board, not floating over it. |
| `scripts/levels/level01_parallax.gd` | Fog / silhouette / MoodTint / `WeatherFx` / `CineFx` / `MoonFill`. Drift follows `wind_vector()`. `cover_layer()` gives every `Parallax2D` plate `repeat_times ≥ 4`. |
| `scripts/levels/level01_east_wing.gd` | Pit beams, `EastFloor` (`skin = "stone"` — the nave is paved, the graveyard is grass), ember ledge, Executioner, ForgeHeart, BossGate, ForgeShelter indoor zone. |
| `scripts/levels/level01_story_beats.gd` | One-shot Director scripts from `GameEvents` + east-wing signals. |

East wing is a helper node, not a PackedScene: instancing a sub-scene would reparent those nodes and break save / story lookups.

Backdrop: `ParallaxBackdrop` is a `CanvasLayer` (layer −10, no viewport follow) holding three `Parallax2D` plates — the original Gothicvania `parallax_sky.png` ×1.9 (moon included), `parallax_mountains.png` ×1.7 and `parallax_graveyard.png` ×1.85 — plus runtime layers: two drifting cloud plates between sky and mountains (`cloud_alpha()`: clear ≈ none, rain overcast), two fog bands and the near silhouette strip. `ParallaxForeground` (layer 1) carries the near grass strip, a world-pinned `GroundFog` band at the knight's waist (`ground_fog_alpha()`) and a screen-fixed `FogVeil` (`fog_veil_alpha()`), so 浓雾 reads as fog and not just a darker tint. Every one of these drifts with `wind_vector()`, as do `WindFx` dust flecks, leaves, rain and tree sway — one wind, many tells. Godot 4.7's `ParallaxLayer` mirroring only ever draws one extra copy, so a 326px mountain tile showed its seam whenever the camera pushed in or shook; `Parallax2D.repeat_times` fixes that. The stacked "normalized" wash (clouds, far mountains, grove, near ground, generated moon/stars) was removed: it read flatter and greyer than the authored plates and its sky did not scroll at all. `ParallaxForeground` (layer 1) is the same construction for the near grass strip.

Set dressing that is not in the `.tscn`:

| Script | Role |
|---|---|
| `scripts/world/solid_platform.gd` | Skins: `ground` (grass + cemetery earth), `floating` (church slabs), `stone` (two flagstone rows cut from `slab_a/b/c` over the same earth), `moss` / `moss_float` (Level02). Collision never changes with the skin. A `ground` step standing on ground (TeachTerrace, pit lips) is authored one tile taller than its rise so its earth covers the grass row beneath it — a mound, not a turf cube on turf. |
| `scripts/world/ruin_plate.gd` | Slices a rectangular wall plate into 8px columns with a deterministic broken crown. Used by `TorchLight` and the altar / gargoyle backdrops; arch plates keep their authored tops. |
| `scripts/world/leaf_shed.gd` | Dead leaves from play-layer trees: 2px, pixel-snapped, pendulum glide with only a few px/s of wind drift, dissolve on the foot line. |
| `scripts/world/wind_fx.gd` | Visible wind: dust / grass / leaf flecks enter from the camera's upwind edge and cross the view at `48 + |wind| × 145` px/s; density from `wind_mote_density()`, none indoors. |
| `ToxinPool.Wisp` | Additive green vapor cells rising off the sludge film, clamped to the film span; rain halves the rate. |
| `EmberNest` | Brazier art from `tools/gen_ember_nest.py`; the flame sprite is bottom-anchored at `FLAME_BASE` inside the well so it burns out of the bowl mouth and soak-shrinks / leans from its root. |

Ambient effects are presentation only: they read `WorldClock` and never write physics, save data, or `Engine.time_scale`. One-shot `Fx` particles parent under the level's `WorldEffects` (via `GameContext.world_effects()`) so they render inside the 640×360 world viewport.

## Levels and routing

`GameContext.LEVELS` registers every authored level (`level01` → `Level01_Static.tscn`, `level02` → `Level02_Undercroft.tscn`). `Director.fade_to(<level path>)` goes through `GameContext.route_scene()`, which records `pending_world_path` and loads `GamePresentation`; the shell instantiates whatever level is pending. `SaveData.meta.scene` names the level; the title's 继续 boots `SaveData.saved_scene()` (unknown scene → Level01).

Save paths are namespaced per level: Level01 keeps its legacy bare paths (`Props/EmberNest`), every later level prefixes its id (`level02:Props/EmberNestShaft`). `SaveData.resolve_saved_node()` refuses to resolve a path from another level, so same-named nodes never collide and a Level01 checkpoint is not a respawn point underground. `SaveData.save_game(scene, player, spawn_override)` lets `LevelExit.travel()` write the *next* level and its arrival point while the knight still stands in the old one (the knight also arrives healed — a chapter break is a rest).

Chapter flow: the forge heart's 复燃 choice no longer returns to the title — the tomb wakes, the floor under the heart gives way and the knight drops into Level02. 熄灭 is still the closing ending.

## Chapters level03–level10 (data-driven)

`GameContext.LEVELS` / `LEVEL_ORDER` register ten levels; `LAYOUTS` maps level03+ to a `ChapterLayout` script. Each chapter scene is just a root running `ChapterLevel` (`scripts/levels/chapter_level.gd`: load save → build layout → spawn knight/camera/HUD → one-shot title beat) with `layout_path` pointing at `scripts/levels/chapters/levelNN_layout.gd`. A layout extends `ChapterLayout` (`scripts/levels/chapter_layout.gd`), overrides the metadata functions (`level_id/title/wake_line/entry_spawn/east_limit/camera_top/theme`) and `build(host)`, and places everything through helpers: `floor_strip/step/platform/enclose/walls/lift/gear`, `toxin_pit/plate_door/rusty_gate/hook/pickup/nest/stele/waymark/exit_door`, `enemy(kind)`, `torch/prop/foliage/hanging`, then `finish()` (backdrop + indoor zone). `ThemeBackdrop` (`scripts/levels/theme_backdrop.gd`) provides the backdrops: `undercroft`, `forge`, `cathedral`, `town`, `industrial` (Parallax2D layer stacks + fixed mood) and `graveyard` (Level01's plates rebuilt, then `Level01Parallax` for clouds/fog/weather). `exit_door(..., next_level_id)` chains levels via `LevelExit.travel` and the next layout's `entry_spawn()`; `requires_flag` locks a door until e.g. a boss dies. The chapter maintenance contract is `docs/level_authoring.md`.

`LevelSanity` (`scripts/levels/level_sanity.gd`) is the geometry police for every registered level (`tests/level_sanity_test.gd`, filterable with `RUSTGRAVE_LEVEL_FILTER`): grounded props/enemies/decor must stand on a platform top, airborne enemies must not be embedded, toxin pools must lie in a pit, pickups may hover only over a platform or beside a hook, platforms may not sit at the origin, and the exit, every ember nest and required plate must be reachable from the spawn by single jumps (≤34px rise, ≤72px edge-to-edge gap, longer drops and lift decks). `reachable_segments` and `is_reachable` default to `allow_hook=true` for compatibility; chapters 3–10 explicitly disable hook edges for their main-route checks. Ceiling tops are excluded. Pressure-plate feet share the same contact tolerance across chapter checks. Decor planted through `Level01Env.plant` / `ChapterLayout.prop` joins the `grounded` group with a `feet` metadata point. This is what caught Level01's three steles buried 30px in the ground and Level02's plate sunk into its ledge.

### Vertical space and encounters

`ChapterLayout.finish()` sizes the indoor zone from the chapter camera top and east limit, covering the room down to y=464. `ThemeBackdrop` repeats indoor plates vertically for tall chapters. Bell Tower is 1280px wide: the floor at y=320 connects through four 240px lifts to the summit at y=−640. Its camera top is −832, ceiling −800, chains anchor below the ceiling, and upper galleries use 16px slabs so they leave the routes underneath open. Three nests provide entry, gallery and summit recovery.

Skeletons rise before becoming tangible; fire skulls alternate patrol, pursuit, lunge and retreat. Nightmare has 16 HP, enters its second phase at half health and summons two skulls on every third second-phase attack, capped at four living summons. Arena bounds constrain the horse and its summons; corridor pursuers in level10 stay west of the arena and its checkpoint. Optional `GhostEnemy.arena_left/right` bounds default to infinity so existing encounters retain their behavior.

Nightmare death persists `nightmare_dead` immediately through `SaveData.persist_story()`. Layout reconstruction skips that boss when the flag is present. The final door requires this flag, saves `game_complete`, plays Chinese ending captions and fades to the title. These are ordinary story flags within save version 1. The original snuff ending remains available in level01.

`chapter_progression_test.gd` loads real chapter scenes to verify exit arrival, inherited heat forge, checkpoint/door restoration, cross-level path isolation and finale persistence. It may position test actors directly. `CampaignWalkthrough` instead extends the introductory input driver, reads geometry to select normal actions, and navigates the entire campaign with isolated saves. It visits all nests and plates, tests title/Continue in the tower and after Nightmare, and has a separate basic-abilities mode. Results and rendered evidence are recorded in `docs/acceptance.md`.

## Level02 (`scenes/levels/Level02_Undercroft.tscn`, 锈墓・贰 — 沉钟地窟)

The `.tscn` is only the root and five empty groups; `Level02Layout.build(host)` places everything from constants so tests can build the level on a bare host without the scene's `_ready`. `level02_undercroft.gd` handles load/spawn/camera/HUD and the one-shot title beat. Entirely indoors: `WorldClock.set_zone(INDOORS)` plus a level-wide `AtmosphereZone`; the HUD line reads `地下 · <phase>`.

| Piece | Role |
|---|---|
| `SolidPlatform` `moss` / `moss_float` | Moss-capped teal brick cut from the Old Dark Castle interior set (`tools/gen_moss_tiles.py` → `assets/env/moss_*.png`). `_build_slabs()` is shared with `stone`. |
| `scripts/world/moving_platform.gd` | `MovingPlatform` (AnimatableBody2D, `sync_to_physics`): cosine shuttle between `position` and `position + travel`, two chains drawn up to `chain_top_y`. LiftC crosses pit C horizontally; LiftD rises to the hidden alcove above the rust gate. |
| `scripts/enemies/ghost_enemy.gd` | `GhostEnemy`: dormant → `appear` when the knight is within `wake_range` → drifts through walls toward the knight, lunges within `attack_range` → after `haunt_time` it vanishes and re-forms `REPHASE_OFFSET` behind the knight. Only tangible while haunting/attacking; 2 HP. Frames from `assets/characters/ghost/`. |
| `scripts/interactables/level_exit.gd` | `LevelExit`: a door. Captions → flag → `travel()` to `target_scene`, or (empty target) a chapter finale that saves in place and fades to the title. `BellDoor` ends Level02 with `undercroft_done`. |
| `scripts/levels/level02_backdrop.gd` | No sky: solid void colour, the castle interior wall (`scroll 0.42`), column silhouettes (`0.66`), a fixed cool `MoodTint` that breathes ±3%. `CineFx` only — no weather, wind or moon layers. |
| `ToxinPool.tint` | Level02 pools are tinted acid yellow-green (`TOXIN_TINT`) — against moss caps the default liquid read as another moss floor. |

Layout (floor y = 320, every step ≤ 32px rise): shaft drop + `EmberNestShaft` + stele + sign → pit B on three moss stones (ghost wakes on landing) → spitter ledge whose pressure plate opens the hall door → scrapper hall → pit C by LiftC → `EmberNestHall` → rust gate (heat forge) → LiftD / alcove stele → gallery, second ghost, gear-shield guard → `BellDoor`.

## Lighting

Night is a cold corridor (`mood_tint` ≈ 30–40% luminance). Lights carve warm pools; HUD / pause / Director stay on isolated canvases.

| Node | Script | Role |
|---|---|---|
| `WorldLight` | `scripts/world/world_light.gd` | Additive PointLight2D. `follow` is `nest` / `indoor` / `heart`. Shadows on. |
| `EmberNest/NestLight` + `Halo` | planted by the nest | Lit fire only: warm pool + additive glow sprite. Unlit = energy 0. |
| `DisplayFit` | `scripts/ui/display_fit.gd` | Keeps the pixel-safe integer presentation and saved window dimensions. Not an Autoload. |
| `MoonFill` | `Level01Parallax` | Weak cool `DirectionalLight2D`. Off indoors and on the title. |
| `ForgeShelter/WarmPool` | `Level01EastWing.place_forge_shelter` | Large dim indoor fill. |
| `ForgeHeart/HeartLight` | `forge_heart.gd` | Residual heat after `unlock()`. |

`SolidPlatform` / `GearPlatform` already carry `LightOccluder2D`. Purification shrine does not emit. No eighth Autoload.

`WorldAtmosphere` owns smooth outdoor/indoor tint and background hierarchy. `WorldLight` changes energy/radius during a doorway transition while keeping one blend mode, so lighting never pops between additive and mixed compositing. `WeatherFx` caches ground and water spans and maps hits through the world viewport transform.

## Player (`scenes/player/Player.tscn`)

| Child node | Script | Role |
|---|---|---|
| root `CharacterBody2D` | `player/player.gd` | Orchestrates children each frame |
| `PlayerController` | `player/player_controller.gd` | Heavy-momentum locomotion, dash/jump gating. Drives any body via `physics_tick(body, delta, move_scale)` |
| `Health` | `player/health.gd` | HP pool with i-frames & death latch |
| `ToxinMeter` | `player/toxin_meter.gd` | Sludge exposure → overflow ticks |
| `RustCoreInventory` | `player/rust_core_inventory.gd` | Pouch/socket ability cores |
| `MeleeCombat` (`Node2D`) | `combat/melee_combat.gd` | Slash state machine: windup → active (== parry window) → recovery |
| `HookshotTether` | `player/hookshot_tether.gd` | Grapple + heat-forge melt hook |
| `Resonance` | `player/resonance.gd` | Dual-core combo window after a parry |

## Combat

- `melee_combat.gd` — on ACTIVE frames a per-idle-frame sweep feeds overlapping projectiles into `Projectile.deflect()` (bounces them home at their source). Parry is not a separate action.
- `hitbox.gd` / `hurtbox.gd` — thin tagged volumes (layers: world 1, player 2, enemy 4, player_hitbox 8, projectile 16, hurtbox 32, interact 64).

## Data

- `data/ability_ids.gd`, `data/ability_catalog.gd`, `data/rust_core.gd` — immutable core definitions (kiln ⇒ Heat Forge, tether ⇒ Hookshot Tether, ember ⇒ Ember Step).

## Progress snapshots and testing

`SaveData.persist_progress()` writes player state, pouch/sockets, consumed paths, switches, Boss flags, checkpoints, weather and ending state as one atomic snapshot. The saved identifier remains `scenes/levels/Level01_Static.tscn` even though the presentation wrapper owns display. Legacy absolute node paths are resolved, and uncertain old pickup records are made obtainable again after a `.before_progress_repair.bak` backup.

Zero-dependency harness under `tests/`. See the Testing section in `README.md`.
