extends RefCounted
## Only original-based redraws are registered. Logical sizes always come from
## the original texture, so replacement artwork cannot reflow scene geometry.
const REPLACEMENTS := {}
