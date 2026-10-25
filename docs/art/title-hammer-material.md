# Title trip-hammer material

The title hammer previously loaded 36x56 and 18x14 source PNGs directly, then
doubled their world scale. At 2560x1440 one source texel covered eight screen
pixels. The right column and bearing were also clipped by the body canvas.

`tools/gen_title_hammer.py` now draws the assembly from original geometry at
eight texels per local unit: body 352x448, head 144x112, link 176x56. The body
uses a 44x56 logical canvas with the same (18,44) origin. Its extra width includes
the complete journal housing without shifting the anvil or the strike point.

The drawing includes an I-beam web, clamp collars, journal rings, pin fasteners,
gussets, replaceable striking shoe, stamped casting plates and ground steel
edges. Material fields add clustered oxide, casting cavities and lamination
marks; explicit scratches follow working edges. These are native drawings,
not sharpening or enlargement of the previous PNGs.

`DensityTextures` retains logical sizes while loading the native companions.
The rotating link maps its two pin centers onto the existing attachment points.
Hot billet layers retain darker mill scale. Timing, strike signals and the
existing additive glow use the same behavior and node budget.

Regenerate with `python tools/gen_title_hammer.py` (Pillow and numpy required).
The bulk QHD builder invokes this drawing source and preserves its 8x density.

Verification: 73 title tests passed with zero engine errors. Windowed GPU
captures cover cold, act2, keep and snuff at 2560x1440 and 1920x1080. Local
evidence is under `screenshots/acceptance/title-machinery-detail/` (ignored by
Git); these fixtures use isolated save/settings directories.
