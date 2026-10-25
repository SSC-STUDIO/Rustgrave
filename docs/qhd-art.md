# QHD artwork and native rendering

Target: 2560×1440. The world remains 640×360 logical units, rendered at up to
four physical pixels per unit; UI remains 1280×720 logical units.

## Original bosses

`tools/art/gen_qhd_bosses.py` rerasterizes the seven independent, editable
original drawings at density 4. Geometry and strokes are scaled before drawing;
physical-pixel material edge lights are applied afterwards. This does not resize
the delivered low-resolution PNGs. Logical canvases, separate clapper/tool parts,
action counts, phase variants and animation anchors remain unchanged.

459 frames live under `assets/qhd/characters`; `assets/qhd/bosses.json` records
their physical dimensions, logical dimensions and SHA256. `ArtTexture` uses an
ImageTexture size override so hframes, sprite rectangles and atlas crops continue
to use logical units. The original resource path is retained for diagnostics.
Missing detailed siblings fall back to the original texture.

The complete boss set would occupy 570.07 MiB as RGBA. It is loaded on demand.
The shared animation cache is an LRU capped at 96 MiB; active sprites retain
their own frames independently. The texture lookup holds weak references.
This is a cache budget, not a cap on total active scene memory.

Validation (2026-10-25):

- `tools/run_tests.ps1 -CaseFilter art_texture`: 3/3, zero engine errors.
- `tools/run_tests.ps1 -CaseFilter original_`: 18/18, zero engine errors.
- `python -B tools/art/audit_qhd_art.py --reproduce`: 459/459 match the
  generator, binary alpha, original canvas ×4, all differ from nearest enlargement,
  zero identical frames between different bosses.
- Evidence: `screenshots/acceptance/qhd/{loader-tests,boss-tests,art}/`.

These checks establish asset integrity and integration. Rendered appearance,
whole-game acceptance and performance are recorded separately below as completed.

## Connected fire

`tools/art/gen_qhd_fire.py` draws new shrine and forge fire without external
image inputs. Tongues bend and rise from a fixed root; the bright core remains
near the fuel. Both strips have eight phases at 12 fps, with density-1 fallbacks
and density-4 artwork. The forge includes refractory courses, coals and an iron
grate; its flames now animate. Existing sparks remain the separate particle layer.

The shrine keeps its 16×24 logical frame, bottom anchor and rain behavior. The
forge keeps the 60×66 logical aperture and original scene node/placement.
`qhd_fire` 2/2, `ember_nest` 9/9 and `title_world` 20/20 passed with zero engine
errors. A QHD rendered title was inspected in `screenshots/acceptance/qhd-fire/`.

## Scene, character and UI detail

The delivery contains 1,166 density-4 PNGs: 459 boss frames, 696 material-set
images, nine title geometry/gear sheets and two fire strips. All keep their
original logical rectangles; higher physical resolution adds detail rather than
enlarging the actors or reducing the camera's field of view.

`tools/art/gen_qhd_title.py` evaluates the editable title geometry at 4×4 sample
phases, then adds fine rivets, joints and instrument markings. It does not read
the old title PNGs as drawing inputs. Gear curves are rasterized directly at
density 4. The largest gear sheet is 4480×2240 physical pixels.

The material set comprises 348 character images, 321 environment images, two
weapon images, four title actor/lamp images and 21 UI images. Within this set,
50 mechanical props are original geometry drawn by `tools/draw_mechanical_props.py`
at both fallback and QHD density: valves, broken machines, braces, panels, chains
and warning plates. Theme regeneration calls the same drawer, preserving these
designs. The title logo is sampled again from its outline font.

The remaining 645 material images are derived refinements of existing raster
designs, not new character drawings. `tools/art/gen_qhd_materials.py` preserves
their palette masses and adds physical-pixel facet edges, silhouette chamfers,
stone chips and metal engraving. No interpolated enlargement, blur or sharpening
is used for this treatment. The material manifest records the method per image.
Twenty-eight low-frequency atmospheric/light masks or obsolete boss fallbacks
are intentionally retained; unused external source packs are not runtime artwork.

World, UI, effects and procedural scene builders use `ArtTexture`; directly
bound scene sprites are adapted before entering the world tree. Ground-contact
scans convert physical alpha bounds back into logical units. A GPU checkerboard
probe exposed region UV clipping by half a logical texel; `ArtTexture.draw_region`
disables that inset so every physical edge texel survives nearest sampling.

Density is capped at four world pixels per logical unit. QHD receives native
world detail; 4K output scales this density rather than claiming native 4K art.

## Rendered acceptance, 2026-10-25

- Material integration: `qhd_material` 3/3; logical rectangles, ground contact
  and packed-scene transforms preserved.
- Prop-fit regression: 7/7, zero engine errors. The first complete run found
  opaque metal-panel corners and three empty physical rows below machinery.
  The mechanical drawer now cuts plate corners and paints the full inclusive
  final source-pixel row at density 4. The checks were retained unchanged;
  the failed run remains in `qhd/full-tests-final/`.
- Scene audit: 707/707 SHA256, dimensions and environment bottom anchors pass;
  all differ from nearest enlargement. Boss audit separately reproduces 459/459.
- GPU sampling: all five checks pass (sprite frames, atlas crops, sprite regions,
  draw regions and tiled drawing), on an RTX 4060 Laptop GPU.
- Display matrix: nine resolutions × four fixtures = 36 captures, plus nine
  title captures; report `passed=true`, no errors. Sizes include 640×360,
  1080p, QHD, 4K, ultrawide and 16:10.
- All 14 chapters have 29 QHD parked-camera images, including the seven bosses;
  contact sheets and selected full-size frames were inspected. These are visual
  fixtures, with actor/camera overrides, and do not establish campaign completion.
- QHD normal-input acceptance: first chapter boss, death/reload, title Continue,
  chapter-two entry, pit crossing and checkpoint Continue pass. Public assists
  remain 1.0/1.0/1.0; one death, zero engine errors. All 38 PNGs decode at
  2560×1440. This is a fresh first-chapter run, not a new 14-chapter playthrough.
- QHD offscreen performance probes: title callback interval p95 3.355 ms;
  level05 active p95 3.302 ms. These short fixed-camera callback measurements
  exclude physical presentation and do not establish worst-case gameplay FPS.

Evidence remains local under ignored `screenshots/acceptance/`:
`qhd/{art,sampling,perf}/`, `display/report.json`, `qhd-title/`, `qhd-chapters/`
and `input-20261025-121524-769/`. The input report records captured image size
(the root texture's logical size can differ on HiDPI Windows);
its fixed-60-Hz accelerated simulation is not a display benchmark.

Reproduce with the bundled Pillow/numpy Python runtime:

```text
python -B tools/art/gen_qhd_bosses.py
python -B tools/draw_mechanical_props.py
python -B tools/art/gen_qhd_materials.py
python -B tools/art/gen_qhd_title.py
python -B tools/art/gen_qhd_fire.py
python -B tools/art/audit_qhd_art.py --reproduce
python -B tools/art/audit_qhd_scenery.py
```

Import changed PNGs in Godot before rendering. Run the sampling scene in a real
GPU window: `res://scenes/tools/QhdSamplingProbe.tscn`. Normal-input QHD capture:
`./tools/run_input_acceptance.ps1 -Ending rekindle -Rendered -Fast -Window 2560x1440 -Shots`.
