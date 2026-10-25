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
