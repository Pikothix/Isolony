# Procedural Rock Control Surface

Inspect these files first when tuning rocks:

- `scripts/procgen/rock_profiles.gd`: active rock baseline, palette sources, biome flavour mapping, archetype selection, and which size tiers are live versus merely available.
- `scripts/procgen/proc_boulders.gd`: low-level drawing and composition math for each rock archetype.
- `scripts/world/props/prop_visual_config.gd`: runtime entry point that applies the active rock baseline to spawned rock props.
- `scripts/world/props/prop_prewarm_config.gd`: cache-prewarm scope for active rock archetypes, biome tags, and size tiers.

Current live baseline:

- Runtime rocks use only the `medium` and `large` size tiers.
- Prewarm mirrors that same medium/large rock scope.
- Active prewarm archetypes are `rounded`, `flat`, `blocky`, and `tall`.
- Runtime biome tags come from terrain mapping in `rock_profiles.gd`; `default` remains a runtime fallback but is not part of the active prewarm sweep.
- Small rocks remain intentionally inactive. They are preserved as a future-facing option only, including any later surface-clue/pebble-style experiments.

Still intentionally code-heavy:

- Boulder shape composition and pixel math remain in `proc_boulders.gd`.
- Rock selection is still deterministic code, not a fully data-driven authoring system.
