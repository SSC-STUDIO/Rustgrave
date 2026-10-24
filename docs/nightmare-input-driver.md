# Nightmare input acceptance

This is the targeted finale input driver for the authored `level10` ring
(`2240..3968`, initial Boss feet `3504/320`). It replaces the old finale's
`1668/1190` combat targets and `620` death target. Runtime Boss, health, combat,
checkpoint and persistence code are unchanged.

## Input strategy

The driver reads clear spans of the live ring platforms, including pillar and
altar obstructions. Ordinary jumps cross the upper gallery to
`RingStairEastLow`. The knight turns toward the horse and uses ordinary sword
attacks from the stair while the real Boss charges, rests, summons skulls and
changes phases. The three phase milestones use the real `phase()` value.

After the real kill, the driver follows the gallery back toward the west stair
and the `ReturnE` balcony. It drops through the adjacent gap and walks beneath
the balcony to `SlagHallEast`. Nearby real enemies are fought with the sword.
The driver observes `GameEvents.hit` and requires the fatal hit to come from
the actual `SlagHallEast` cyclic hitbox, followed by a new living player and an
incremented death count. It verifies `nightmare_dead` and Boss absence after
death, then uses pause/title/Continue and checks both again.

The only controls after staging are movement, jump, dash/attack through existing
navigation helpers, interact and UI. The driver does not assign actor positions,
HP, inventory, progress flags or Boss state, and does not emit combat events.
Public assists are incoming `0.5`, parry `1.5`, toxin `0.5`.

## Local fixture scope

`NightmareInputFixture.tscn` is explicitly **LOCAL FINALE FIXTURE; NOT FULL
CAMPAIGN**. Before input begins it loads the complete real final chapter,
places the default knight once at the authored arena nest, and omits the initial
`ArenaGate`. This avoids manufacturing a kiln core or campaign progress flag.
The real nest is lit with interact, including its normal heal/checkpoint save.
The real Boss, corridor enemies, summons, cyclic hazards and arena are live.
The omitted entrance gate is rebuilt normally on death/Continue.

`run_nightmare_input_fixture.ps1` supplies an isolated `APPDATA` directory. Its
save deletion and checkpoint writes do not use the player's ordinary save.
The JSON records the setup exception, starting HP, checkpoint HP, no granted
items/flags, all phase/kill/reload/Continue milestones, exact fatal source,
engine errors, persisted death flag and final Boss absence.

This fixture does not prove arrival from a legal full-campaign save, completion
of the final ending choice, or full-campaign visual acceptance.

## Reproduce

```powershell
./tools/run_nightmare_input_fixture.ps1 -ArtifactsDir screenshots/acceptance/nightmare-input-local/final-headless
./tools/run_nightmare_input_fixture.ps1 -Rendered -ArtifactsDir screenshots/acceptance/nightmare-input-local/final-rendered
./tools/run_tests.ps1 -CaseFilter nightmare_input_route -ArtifactsDir screenshots/acceptance/nightmare-input-local/tests-route
./tools/run_tests.ps1 -CaseFilter nightmare_boss -ArtifactsDir screenshots/acceptance/nightmare-input-local/tests-boss
./tools/run_tests.ps1 -CaseFilter level10_layout -ArtifactsDir screenshots/acceptance/nightmare-input-local/tests-layout
```

Run serially. Rendered output uses accelerated fixed 60 Hz simulation; it is
visual input evidence, not a performance benchmark. Reports and PNGs remain in
the ignored acceptance artifact directory; source, runner and regression tests
are versioned.

## Verification

Verified on 2026-10-24 with Godot 4.7.1 stable. Source change:
`d508390` (`codex/nightmare-input-acceptance`, base `70920d7`).

| Run | Result | Evidence |
| --- | --- | --- |
| Local headless real combat | Pass; phases 1/2/3, kill, one real death, Continue | `final-headless/result.json` |
| Local rendered real combat | Pass; same complete sequence, 1920×1080 | `final-rendered/result.json` |
| Input route geometry | 2/2 cases, 59 assertions | `tests-route/summary.json` |
| Native Nightmare Boss regression | 10/10 cases, 98 assertions | `tests-boss/summary.json` |
| Native final chapter layout | 21/21 cases, 298 assertions | `tests-layout/summary.json` |

All evidence paths above are relative to
`screenshots/acceptance/nightmare-input-local/`. The targeted regressions total
33/33 cases and 455 assertions; every run reported zero engine errors.
No full suite was run.

Both input runs began without `nightmare_dead`, with default sword damage 1,
maximum HP 7, and the real nest's checkpoint heal to 7. The headless run observed
six accepted slag hits and the rendered run four. Both fatal sources were
`/root/GamePresentation/WorldViewport/Level10_ForgeCore/Props/SlagHallEast`.
Both ended with `nightmare_dead=true` and `boss_absent=true` after Continue.
Other corridor enemies remained live, and the rendered run also took normal
combat damage; no damage immunity was used.

The rendered run saved seven 1920×1080 milestone PNGs in
`final-rendered/userdata/Godot/app_userdata/Rustgrave/`: ring approach, each of
the three phases, slain, death reload and Continue. All seven were inspected
in `final-rendered/contact-sheet.png`; phase three and death reload were also
inspected at full resolution. The Boss, stair, upper gallery and HP/phase HUD
are visible; phase transition red flash is captured in the phase PNGs. The
reload PNG shows the real checkpoint and normal recovery banner. Boss absence
after reload is asserted against the world, not inferred from that checkpoint
camera's view.

Legal campaign arrival at the final chapter and the final ending sequence
remain the root campaign driver's separate acceptance responsibility.
