# Procedural Tree Control Surface

Inspect these files first when tuning trees:

- `scripts/procgen/tree_profiles.gd`: active tree baseline, palette sources, biome flavour mapping, archetype selection, and which size tiers are live versus merely available.
- `scripts/procgen/proc_trees.gd`: low-level drawing and composition math for each tree archetype.
- `scripts/world/props/prop_visual_config.gd`: runtime entry point that applies the active tree baseline to spawned tree props.
- `scripts/world/props/prop_prewarm_config.gd`: cache-prewarm scope for active tree archetypes, biome tags, and size tiers.

Current live baseline:

- Runtime trees use only the `large` size tier.
- Prewarm mirrors that same `large`-only tree scope.
- Active prewarm archetypes are `deciduous`, `conifer`, and `dead`.
- Runtime biome tags come from terrain mapping in `tree_profiles.gd`; `default` remains a runtime fallback but is not part of the active prewarm sweep.

Still intentionally code-heavy:

- Branch/canopy drawing math remains in `proc_trees.gd`.
- Tree selection is still deterministic code, not a fully data-driven authoring system.
