extends RefCounted
class_name ElevationEdgeVariantResolver

## Purpose: Resolve presentation-only elevation edge masks to current TileSet placeholder variants.
## Responsibility: Convert background cliff readability masks into terrain visual variant keys.
## Assumption: TerrainConfig owns the optional atlas coordinates for each returned key.

const MASK_NORTH := 1
const MASK_WEST := 2
const MASK_NORTHWEST := MASK_NORTH | MASK_WEST

const VARIANT_FLAT := "flat"
const VARIANT_EDGE_NORTH := "edge_north"
const VARIANT_EDGE_WEST := "edge_west"
const VARIANT_CORNER_NORTH_WEST := "corner_north_west"


static func get_variant_key(mask: int) -> String:
	match mask:
		MASK_NORTH:
			return VARIANT_EDGE_NORTH
		MASK_WEST:
			return VARIANT_EDGE_WEST
		MASK_NORTHWEST:
			return VARIANT_CORNER_NORTH_WEST
	return VARIANT_FLAT
