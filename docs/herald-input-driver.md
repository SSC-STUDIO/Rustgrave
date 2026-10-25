# Herald input and ground-area acceptance

The shared campaign driver now handles the airborne `herald_dead` gate through
normal input. The generic Boss path used the Herald's live hover height as a
navigation goal (`2930/170`), where the chapter has no standing surface.
The dedicated branch navigates to the authored `HeraldEastPerch` and attacks
the real low dive with ordinary sword swings and single jumps.

## Separate runtime repairs

`d724dc2` fixes the Herald's existing world/local coordinate error. In the real
chapter the floor is world y320 and the flyer hovers at y170. An updraft placed
at child-local y245 therefore appeared at world y415, below the player's feet.
The wind-push area and the ground telegraphs had the same coordinate error.

Wind/updraft areas now use the actual world floor and remain fixed there while
the owning Boss flies. They remain children of the Boss for cleanup. Their
warnings occupy the same world rectangles; the dive lane marks its real low
hitbox centre. Damage, area dimensions, force, lifetime, warning duration,
attack timing, selection, HP and phase thresholds are unchanged.

`herald_world_zones_test.gd` covers a nonzero parent transform and floor, real
Area2D overlap, continued cleanup ownership, independence from Boss movement,
wind application and a normal jump through the real updraft. The real controller
jumped 38.97px normally and 67.07px in the unchanged first-phase updraft.

`78690c1` fixes a second existing issue found by the input replay: the real kill
persisted `herald_dead`, but rebuilding level09b spawned the defeated Boss
again. The chapter now omits the cleared encounter in campaign play, including
its arena, hazards and approach trigger. Boss Rush still receives its real
rematch. Added regressions save through the real nest, kill only inside the
unit fixture, clear in-memory flags, reload the disk save, and check the real
exit; the separate input replay performs the actual fight.

## Input driver

`3d0ca6a` adds only the Herald branch and `_herald()` in the shared driver,
plus the standalone checkpoint replay and its runner. It reads the real east
perch instead of assigning an actor position. It faces the Boss, swings normally,
and starts a single jump during the final 0.12s of the real dive warning.
The ordinary sword can also deflect the real feather projectiles. The bounded
loop waits for normal death/respawn if a combat attempt fails.

The fixture asserts an actual kiln core/heat forge, no hook and no extra jump.
It never stages actors, grants HP/items, opens gates, writes progress flags,
emits hits or directly damages the Boss. Public assists are incoming 0.5,
parry 1.5 and toxin 0.5. The two runtime repairs are not driver workarounds.

## Isolated legal checkpoint replay

`HeraldInputFixture.tscn` is explicitly **LOCAL HERALD CHECKPOINT REPLAY; NOT
FULL CAMPAIGN**. The runner copies the supplied legal campaign save unchanged
to isolated APPDATA, verifies the copied SHA256, then uses the real title's
Continue. The source save is not rewritten. The restored player starts at
`2684.618/319.9253`, HP/max HP 8, with `level09b:Props/EmberNestGate` as checkpoint
and Herald still alive.

After the real kill the fixture returns through pause/title/Continue, verifies
Boss absence and the saved kill flag, walks to the actual exit, interacts and
checks arrival in level10. The report records both phases, real melee and
reflected hits for the winning attempt, zero hook yanks, deaths, engine errors
and the input source save hash. The reported damage is the sum of accepted
damage events, including normal overkill.

```powershell
./tools/run_herald_input_fixture.ps1 -SourceSave <legal-level09b-checkpoint.cfg> -ArtifactsDir screenshots/acceptance/herald-input-local/final-headless
./tools/run_herald_input_fixture.ps1 -Rendered -SourceSave <legal-level09b-checkpoint.cfg> -ArtifactsDir screenshots/acceptance/herald-input-local/final-rendered
./tools/run_tests.ps1 -CaseFilter herald -ArtifactsDir screenshots/acceptance/herald-input-local/tests-world-and-native
./tools/run_tests.ps1 -CaseFilter level09b_layout -ArtifactsDir screenshots/acceptance/herald-input-local/tests-layout-persistence-02
```

Run serially. Rendered replay is accelerated fixed 60 Hz visual evidence,
not a performance benchmark. The checkpoints, JSON and PNG evidence are ignored
local artifacts; source, runner and regressions are versioned.

## Verification

The headless legal-checkpoint replay passed with zero deaths and zero engine
errors. The winning attempt registered five real sword hits, two reflected
projectile hits and zero hook yanks. Continue omitted the defeated Herald and
retained `herald_dead`; interacting with the real exit arrived in level10.

Herald native/world-area regressions passed 9/9 cases, 64 assertions. The full
targeted level09b layout file passed 16/16 cases, 243 assertions, including disk
reload and Boss Rush. Both groups reported zero engine errors. This agent did
not run the full suite.

The rendered replay also passed with zero deaths and zero engine errors on
Godot 4.7.1, OpenGL Compatibility, NVIDIA RTX 4060 Laptop GPU. The winning
attempt registered five real sword hits, one reflected projectile hit, 20
accepted damage and zero hook yanks. Both phases, the kill, Continue absence
and the real exit into level10 passed. The log contains one Control-anchor
warning; it contains no engine errors.

All eight milestone PNGs are 1920x1080 and were reviewed in a contact sheet;
the second-phase and kill frames were also inspected at full resolution.
The combat frames show the actual east perch, floor-aligned warning and phase
transition. The kill frame has no Boss or Boss bar. Continue frames show the
restored nest. The initial-checkpoint and level10-arrival images were sampled
during scene fades and are dark; arrival is established by the fixture's real
scene assertion and result JSON, not by those transition images.

Final local evidence is under
`screenshots/acceptance/herald-input-local/`: `final-headless/result.json`,
`final-rendered/result.json`, `final-rendered/herald-contact-sheet.png`, and the
eight PNGs in `final-rendered/userdata/Godot/app_userdata/Rustgrave/`.
The targeted regression summaries are `tests-world-and-native/summary.json`
and `tests-layout-persistence-02/summary.json`.

Both replays used the unchanged legal campaign save from
`overhaul-v3-completion/Rustgrave/screenshots/acceptance/input-20261024-200012-518/rekindle-userdata/Godot/app_userdata/Rustgrave/input_walkthrough_rekindle.cfg`.
Its source SHA256, recorded in both result files and rechecked after the runs,
is `5CE73967A0B80E7AB6E36504F5B7EDAC025F625FCF623D53AB0AFA081C4BC122`.

Full arrival from a new game, the preceding chapters and final campaign ending
remain the root campaign driver's separate acceptance responsibility.
