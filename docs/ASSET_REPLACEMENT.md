# Asset Replacement Guide

This project keeps simulation identity/state separate from replaceable presentation. Art changes must not alter building ids, resource ids/types/yields, occupied cells, construction progress, needs, stockpile totals, depletion ids, or harvest orders.

## Buildings

Building presentation metadata lives in `scripts/buildings/building_definition.gd`:

- `construction_visual_id` and `completed_visual_id` select the current procedural placeholder profiles.
- `construction_scene_path` and `completed_scene_path` may point to replacement scenes whose root is `Node2D` and whose origin aligns with the building origin cell.
- `icon_path` may point to a `Texture2D` used by the Build & Orders button.
- `placeholder_palette` controls the existing fallback drawing colors.

When a state-specific scene path is non-empty, `ConstructionSiteVisual` instantiates it as a child and retains only presentation effect-radius overlays. Empty or invalid paths fall back to the procedural placeholder. Do not put construction completion, storage, warmth, shelter, costs, or occupancy logic in an art scene.

## Resources

Resource presentation metadata lives in `scripts/world/props/resource_visual_definition.gd`. Each stable resource-kind id maps to:

- a default scene path;
- an optional icon path;
- a procedural profile id (`tree`, `rock`, or `none`);
- a placeholder visual id for inspection/debugging.

`ChunkManager` has optional scene overrides for local experiments; when unset, it loads the registry scene. Replacement resource scenes must keep an `Area2D` root using `ResourceNode`, a usable collision shape, and may provide a child named `ProceduralSprite`. Polygon children are fallback art and are hidden when a procedural sprite is active. Resource type, yield, stable id, depletion, and orders are assigned/owned outside visual metadata.

Trees and rocks intentionally remain procedural. Their palettes/archetypes/tier rules live in `tree_profiles.gd`, `rock_profiles.gd`, `prop_visual_config.gd`, and the procgen helpers/cache. Berry Bush art remains scene-local polygon placeholder art.

## Colonists

Colonist art is contained by `scenes/entities/Colonist.tscn`. The current scene combines a sprite, polygon fallback/shadow, selection indicator, and needs label. Replacing the body sprite/polygon does not require simulation changes.

Keep these integration nodes, or deliberately update the optional `get_node_or_null()` lookups in `colonist.gd` if they are renamed:

- `SelectionIndicator` for selection projection;
- `NeedsLabel` for the debug need display.

Identity, needs, skills, traits, relationships, movement, and persistence belong to `Colonist`, not to the sprite or animation nodes.

## UI

Building button display names and optional icons come from `BuildingDefinition`; button nodes do not duplicate those names. Panel layout and debug labels remain in `Main.tscn` and UI scripts. Replacing themes, fonts, panels, or icons must preserve request signals and must not move simulation state into controls.

## Intentional Placeholders

The following remain acceptable presentation-only placeholders:

- procedural Campfire/Cabin/Storehouse scaffolds and completed drawings;
- placement/effect radius overlays;
- tree/rock procedural sprites and profile palettes;
- Berry Bush polygons;
- colonist shadow, selection diamond, and debug needs label;
- terrain atlas previews and debug-level panels.

## Replacement Checklist

1. Change a definition scene/icon path, a resource visual registry entry, scene-local sprite, or UI theme.
2. Keep stable gameplay ids and authoritative metadata unchanged.
3. Confirm scene roots/named integration children still satisfy the presentation contract.
4. Run `Main.tscn` headlessly and validate placement, construction states, resource spawning/designation, and colonist selection.
5. Do not serialize textures, visual profiles, generated sprite cache entries, UI mode, or rendered nodes.
