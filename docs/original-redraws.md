# Original-based redraws

The original asset remains authoritative for composition, palette, transparent
silhouette and logical dimensions. Reference edits supply finer material detail.
Import removes matte pixels and broad changes in lighting or color; tile edges
return to their original colors to retain the existing joins. Texture density is
independent of the world's 640×360 logical coordinates.

The first scenery batch contains 39 source variants from 32 reference edits:
graveyard sky/ridge/graves, forge/industrial layers, tower and interior walls,
altar/window/column pieces, a ruined tower and a brick house. Each entry in
`assets/redrawn/catalog.json` records its source, native output size, density,
drawing and output hash. Originals are not overwritten. Title assets are outside
this batch.

Raw drawings, prompts and layouts are in `art_sources/redrawn` and excluded from
Godot import by `art_sources/.gdignore`. To reproduce one drawing's import without
calling a service:

```powershell
python tools/redraw_asset_pipeline.py compile faithful_parallax_sky --work art_sources/redrawn
```

`prepare` and `prepare-grouped` create local reference sheets only; they make no
network requests. The importer contains no credentials or expiring service URLs.
Single images returned on a service-normalized canvas are registered back to the
original canvas; output density is calculated from their actual returned texels.
Multi-image atlases reject a changed aspect ratio.

Verification: full alpha-mask, dimension and hash checks in Python;
`redrawn_art_test` checks the active Godot texture route; `backdrop_test` checks
all theme layers. Render fixtures and comparisons are under
`screenshots/acceptance/native-scenery-redraw`.

The character batch adds 351 frames across all 12 character folders (the separate
enemy-death effect folder is outside this batch). It preserves original masks,
palettes, canvases and frame sequences. One scale is shared across each action;
partial neighbouring poses at cell edges cannot determine the scale.

The normalized flying-demon idle action uses the original-referenced drawing of
the same creature/action at its larger source size. Five cemetery-hero attack
frames transfer drawn material patches from that hero's completed idle redraw
onto their original attack poses. These are explicitly recorded as reuse/material
transfer, rather than additional service generations.

Character drawings/layouts/prompts are in `art_sources/redrawn_characters`. A
completed action can be rebuilt without network access:

```powershell
python tools/redraw_character_pipeline.py knight_idle --work art_sources/redrawn_characters
```

`transfer_material_details("player_cemetery_hero", "attack")` reproduces the five
material-transfer frames once that character's idle frames have been built.
`redrawn_character_test` verifies the animation route and authored masks;
`density_textures_test` and `player_skin_test` verify texture/skin compatibility.

This is an incremental batch. The other prepared scenery reference edits remain
pending. The selected image service returned code 400,
"API account balance insufficient or no permission", so further submissions
were stopped. These ungenerated assets are not counted as completed redraws.
