# ADR: Scouting, Travel, and the Location Network

## Decision

`LocationRegistry` owns persistent bounded-location identity, deterministic `Vector2i` world positions, lifecycle, generated base data, runtime resource state, piles, and presence membership. Home is fixed at `(0, 0)`. Euclidean distance between these coordinates drives abstract travel; desktop-window pixels never enter simulation.

`ScoutingCoordinator` owns scouting request records, skill-scaled duration, progress, search sequence, and discovery seed. `LocationTravelCoordinator` owns traveller, endpoints, Euclidean distance, bounded duration, progress, and departure time. `WindowedColonyState` validates requests and coordinates atomic presence transitions, local-work cancellation, needs ticks, registry generation, arrival, and save/load.

A colonist is exactly one of present in one location, scouting, or travelling. Scouts and travellers are removed from all location membership. Scouting returns to its origin. Arrival uses the destination's deterministic walkable entry cell. Scout resets to Unassigned; other compatible roles persist.

Lifecycle values are `HOME`, `DISCOVERED`, `RETAINED`, `DEPLETED`, and `DISCARDED`. Retaining does not claim or settle a site. Remote gathering creates remote piles. Remote hauling consolidates loose piles at the entry cell, which is not settlement storage. Resources never transfer between locations.

The separate windowed-colony schema is currently version 4 at `user://windowed_colony_v3.json`; versions 3 and 4 are accepted. It persists complete location records, positions, presence, scouting sequence and active scouting/travel progress. The loader validates exclusive presence before staging registry, building, structural, roster and mobility owners. A non-empty carried payload is rejected at departure and save validation.

Location windows, discovery dialogs, known-location rows, and route overlays are presentation projections. Closing or moving them cannot affect authority. Route rendering reads progress; it never advances it.

## Consequences and deferred work

There is no pathfinding between locations, no inter-location cargo, caravan, road, second primary settlement, or automated logistics authority. Travel uses one base speed with 25–90 second bounds. Remote entry-cell Food is eligible for consumption even though summaries currently classify it as loose; that mismatch is unresolved. Location maps generate once at discovery and render only while open.
# P05 amendment

Retained and claimed are independent states. Claim requires retained lifecycle, a present colonist, no active mobility contradiction, and a non-home target. Claimed locations reject discard. Completed Supply Caches are preferred local haul destinations; without one, remote entry-cell consolidation remains a temporary fallback and never transfers resources between locations.
