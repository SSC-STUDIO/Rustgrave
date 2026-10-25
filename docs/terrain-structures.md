# Grounded terrain

Campaign platforms assemble their load-bearing structures after level construction.
Existing deck names and walkable top coordinates remain the authoring reference.

- A low step with at most 20 pixels below its underside, wholly over a real
  foundation, gets a solid masonry plinth and collision down to that foundation.
- Elevated decks use masonry arcades. Piers and footings occupy the rear depth
  plane; players can walk through the foreground openings. These rear members
  deliberately have no collision in the walking plane.
- Stone footholds meet their supports at the visible sprite underside, rather
  than the bottom of the larger octagonal collision envelope.
- A lift has a fixed gantry spanning its entire horizontal travel. Its ropes
  meet the overhead beam even at the highest stop. Rear posts continue to the
  floor. Moving decks and fragile decks retain their original collision rules.
- Fragile bridge trestles remain standing when the deck collapses.

Support materials come from the chapter's existing masonry/iron textures. The
graveyard's lavender ledges use the middle course of their original church slab.
No separate architectural palette is introduced.

Verification: `terrain_structures_test`, `level_sanity_test`, and
`route_audit_test`; QHD fixtures in
`screenshots/acceptance/native-scenery-redraw/structures-pass2/level01` and
`structures-pass3/level07`. The route audit checks geometry; it is not an input
playthrough or a claim of realistic destruction simulation.
