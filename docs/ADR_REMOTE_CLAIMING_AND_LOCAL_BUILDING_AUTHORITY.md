# ADR: Remote Claiming and Local Building Authority

## Decision

`LocationRegistry` owns retained/claimed lifecycle and claim metadata. A remote claim is valid only for a retained, non-home, non-discarded location with the requesting colonist physically present. Claiming costs no resources and preserves terrain, piles, resources, and presence.

`LocationConstructionCoordinator` is the focused authority for the P05 Supply Cache. It validates the complete 1x1 footprint, owns stable building records and occupied cells, reserves the full local 20 Wood cost, consumes that reservation exactly once on first work, advances bounded Construction-skill work, and activates 100 units of shared Wood/Stone/Food capacity on completion. Insufficient Wood leaves a planned site unchanged.

Supply Cache worker ownership is transient and remains in `LocationConstructionCoordinator`. Assignment reserves unconsumed local materials and the colonist task records the exact building id while walking locally or constructing. Completion, cancellation, abandonment, failed local travel, site removal, and colonist removal explicitly release assignment ownership. Release returns only an unconsumed material reservation; consumed materials and construction progress remain authoritative at the site. A simulation audit clears an assignment only when the worker is absent, away, in another role/location, or no longer targets that exact incomplete cache. Save export/import excludes both worker and material reservation ids, so loaded incomplete caches are unassigned without changing progress or consumed materials.

Supply Cache contents belong only to the completed building record. Local hauling reserves cache capacity before pickup and deterministically prefers the first stable completed cache; remote entry-cell consolidation remains the fallback when formal capacity is unavailable. Home camp storage is unchanged. No inter-location logistics exist.

Placement preview and building visuals are presentation-only and reconstruct from snapshots. Current Windowed Colony Save Version 4 persists claims and building state, accepts version 3 for compatibility, and clears worker, material, capacity, movement, and UI reservations on load. Claimed locations reject discard.

## Deferred

Multiple primary settlements, player-facing arbitrary building placement, demolition, repair, cancellation/refunds, automated logistics, and remote defence remain outside this decision. `campfire`, `cabin`, and `storehouse` definitions are not active windowed gameplay.
