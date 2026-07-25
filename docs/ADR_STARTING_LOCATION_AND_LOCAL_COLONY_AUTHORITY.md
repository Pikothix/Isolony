# ADR: Starting Location and Local Colony Authority

## Status

Accepted for P03.

## Decision

New Game creates one deterministic bounded starting location and three colonist runtime records present there. `WindowedColonyState` owns coordination, phase, seed, time, colonists, requests, and save orchestration. `LocationRegistry` owns generated location state, settlement, resource nodes, physical piles, and the temporary camp storage cell. Presentation owns only projections and desktop state.

Settlement is an explicit, validated transition from `LOCATION_EVALUATION` to `SETTLED`. Before settlement, colonists inspect idly. After settlement, a colonist role selects deterministic local work. Harvest completion mutates registry resources and creates physical piles; Hauling moves those piles to the camp cell. Hunger consumes stored physical Food and Rest can recover through ground sleep.

Low Hunger retains priority over Rest and ordinary role work. A colonist first attempts the registry's authoritative consumable-Food query. If no eligible Food exists, the failed attempt enters transient recovery instead of being repeated every simulation decision: Foraging may gather only its existing Food-producing resources, Hauling may select only loose Food for normal deposit, and all other role work remains blocked. Once Food becomes consumable, the next need decision consumes one unit and resumes the existing eating recovery. The recovery flag is runtime-only and is reconstructed as inactive after load.

The current windowed-colony document is version 4 at `user://windowed_colony_v3.json`, separate from the dormant streamed-world version-2 format. Versions 3 and 4 are accepted. Import validates and stages active owners before replacement, then resets transient work, reservations, and Hunger recovery.

## Consequences

The starter location supports the active scouting/travel network. The coordinator is currently broad and should be monitored as later systems arrive. Local movement now uses `LocationTraversalResolver`; it remains frame-stepped and is not a bulk/offline simulation contract. Camp storage is deliberately one deterministic cell, not a legacy stockpile-zone substitute. Fruit harvest has no regrowth and does not destroy fruit trees.
# P04 amendment

The starting location remains the sole claimed primary settlement at world origin `(0, 0)`. Retained remote locations are explicitly unclaimed. Local roles query only a present colonist's current location; no inter-location resource transfer or remote settlement authority was introduced.
# P05 amendment

Home remains the single primary settlement and keeps temporary camp-cell storage. A retained remote is not owned until a present colonist submits a validated claim. A claimed remote is an outpost, not a second settlement, and may construct only the P05 Supply Cache.
