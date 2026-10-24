# Original BellFounder pixel art

BellFounder is a short, broad furnace worker with four overlapping curved
armour courses and widely planted casting shoes. A low slit visor is built
into the upper course. The back carries an independently recognizable bell
mould furnace with a lifting loop, three riveted bands, barred kiln opening,
live flame and exhaust shutters. Tongs, elbow ratchets, piston ankles and
engraved plate joins give the silhouette a specific casting trade.

The palette is charcoal iron, red copper and molten orange. Phase two
physically unseats a side plate, opens a glowing seam and lifts the exhaust;
it is not a recoloured existing knight. The independent forging hammer has
bevelled faces, three bolted metal courses, wrapped segmented shaft and an
inset forge mark. Its windup lifts the head; active slam plants it low beside
the original attack zone. The existing hammer swing call still rotates it.

All 128 transparent 128x112 PNGs are locally authored by Pillow shapes in
`tools/gen_original_bell_bosses.py --boss bell_founder`, without reading any
character image, using external assets or contacting an image API. Body and
hammer have both phases, idle, hammer slam, mould cast, molten pool, bell shard
and stagger sets. The actual attack ID and actual windup/active/recovery step
pin their two-frame segments together; true broken windows select the cracked
poses. Original `set_hot`, `crack`, `animate` and `set_swing` calls remain valid.

Only this Boss's visual section changes. Shared loaders, battle rules,
collisions, physics, progression and saves retain their original behavior.

The BellFounder group passed 8/8 cases, 186 assertions and zero engine errors.
This includes the existing slam parry, phase, mould, shard, molten-pool and
death tests, plus complete frame sets, real step pinning and preserved hammer
swing/collision contracts. The composite frame overview and real level07b
phase-one and phase-two screenshots were visually reviewed. BossFixture
recorded five RTX 4060 OpenGL captures with zero engine errors. This is staged
art inspection in the actual chapter, not an input playthrough.

Local evidence: `screenshots/acceptance/original-bells/founder-frame-review.png`,
`founder-tests/`, and
`founder-render-userdata/Godot/app_userdata/Rustgrave/boss_fixture/level07b_BellFounder/`.
