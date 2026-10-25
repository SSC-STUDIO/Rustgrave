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

This is an incremental batch. The other prepared reference edits and missing
character actions remain pending. The selected image service returned code 400,
"API account balance insufficient or no permission", so further submissions
were stopped. These ungenerated assets are not counted as completed redraws.
