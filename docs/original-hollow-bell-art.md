# Original HollowBell pixel art

HollowBell is a tall, suspended, nonhuman cracked bell. Its silhouette is a
double forged chain, ring crown, widening bronze body and rolled open mouth.
Three inset name tablets carry individually drawn angular cipher marks.
Cold blue bronze, pale verdigris facets, tiny rivets, casting seams, irregular
patina and chipped edges distinguish it from every humanoid enemy. The second
phase opens a branching incandescent fracture and a broken piece at the lip;
it is more than a palette substitution.

The attackable clapper is a separate original sprite with articulated chain,
bevelled octagonal head and a concentric brass weakpoint. Its visible head
stays inside the existing weakpoint region. Shell sway does not move collision.

All pixels are drawn from authored Pillow shapes in
`tools/gen_original_bell_bosses.py --boss hollow_bell`. No image, sprite,
texture, font or external API supplies character pixels. Transparent PNGs use
the existing `CharFrames` directory convention. The body canvas is 160x336;
the independent clapper is 40x64. The 72 frames cover both phases, idle, four
attacks, stagger and clapper pulse.

The original shell API (`animate`, `set_hot`, `shake_by`) and independent
hammer call remain. The real attack ID and actual windup/active/recovery step
pin two frames per step, so a looping animation cannot imply an early hit.
Real weakpoint stagger selects its own pixels. Shared animation loaders,
attacks, timing, damage, collision, progress and saves are unchanged.

The HollowBell regression group passed 8/8 cases, 148 assertions and zero engine
errors, including all four original attacks and weakpoint/phase/save behavior.
New tests check every transparent frame set, real attack-step pinning and the
unchanged weakpoint geometry. Frame overview and the real level02 phase-one
and phase-two screenshots were visually reviewed. The existing BossFixture
recorded five rendered captures and zero engine errors on RTX 4060 OpenGL.
This is staged art inspection in the real chapter, not an input playthrough.

Local evidence: `screenshots/acceptance/original-bells/hollow-frame-review.png`,
`hollow-tests/`, and
`hollow-render-userdata/Godot/app_userdata/Rustgrave/boss_fixture/level02_HollowBell/`.
