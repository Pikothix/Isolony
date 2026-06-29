# ADR A01 — Architectural Baseline

## Status

Accepted

## Date

2026-06-29

## Context

The current Godot 4.7 Colony Sim prototype has working world generation, chunk streaming, construction, colonists, focused jobs, physical resources, hauling, UI projections, and a minimal save foundation. The architecture audit and documentation sync identified clear current owners alongside several prototype boundaries that are safe to retain temporarily but must not be mistaken for long-term authority models.

This record establishes the implemented architecture as the baseline for subsequent milestones. It does not introduce a new system or approve an implementation change.

## Decision

- `WorldState` remains the main simulation authority.
- `Main` remains the scene coordinator and dependency injector.
- UI may request actions and present state, but must not own simulation state.
- Rendering and projection nodes must not become authoritative.
- `ChunkManager` currently owns chunk streaming, manual terrain deltas, depletion ids, live resource indexing, and world projections.
- `ResourceStockpile` owns abstract stored totals, shared capacity, construction earmarks, and haul capacity reservations.
- `ColonistManager` owns population lifecycle. Individual `Colonist` nodes currently own persistent colonist records.
- `SaveGameService` remains a non-autoload helper until a specific architecture decision changes that boundary. No autoload may be introduced without explicit review.
- Save/load remains minimal and non-transactional. `S1 Save Contract Hardening` added whole-document structural preflight, but owner imports still mutate incrementally after preflight.
- Loaded `ResourceNode` participation in live harvest validation is accepted as temporary technical debt, not as the intended long-term resource authority model.
- `TimeState` pause and scale currently affect clock state only, not the complete simulation.
- `ReachabilityQuery` is the stateless loaded-cell reachability boundary. Individual `Colonist` nodes own only transient current path state and continue to own their persistent position records.
- `WorldState` exposes bounded deterministic availability snapshots for each implemented work type. `Colonist` performs transient reachability and priority selection over those snapshots; this is not a shared job board.

## Current Ownership Baseline

| Area | Current owner | Boundary |
|---|---|---|
| Scene composition and dependency wiring | `Main` | Routes input and requests; does not own simulation records |
| Core colony state | `WorldState` | Owns construction, harvest orders, stockpile zones, ground items, focused reservations, and derived building-effect queries |
| Clock/day-night state | `TimeState`, owned by `WorldState` | Pause/scale applies only to clock advancement |
| Abstract storage | `ResourceStockpile`, owned by `WorldState` | Owns totals, capacity, construction resource earmarks, and haul capacity reservations |
| Generated world rules | `WorldGenerator` and `TerrainConfig` | Deterministically reconstruct base terrain and spawn inputs from code-backed rules and saved configuration |
| Streamed world and world deltas | `ChunkManager` | Owns loaded chunks, manual terrain overrides, depletion ids, live resource index, and reconstructible projections |
| Loaded-cell reachability | `ReachabilityQuery` | Reads `ChunkManager` and `WorldState`; owns no authoritative state, cache, or persistence |
| Generated resource interaction | Deterministic spawn data, `ChunkManager`, and loaded `ResourceNode` | Current split authority is temporary; `WorldState` still owns harvest intent and ground-item publication |
| Population lifecycle | `ColonistManager` | Creates, replaces, exports, and resolves the live population |
| Individual colonist records | Each `Colonist` node | Owns identity, position, needs, skills, traits, relationships, and work priorities |
| UI and presentation | `Main`, UI panels, and projection nodes | May read state and submit validated requests; owns only transient control/presentation state |
| Persistence coordination | `SaveGameService` | Non-autoload helper coordinating current owners; not a production save UI or transactional loader |

## Accepted Temporary Risks

- Resource authority is split across deterministic spawn data, `ChunkManager`, and loaded `ResourceNode` records.
- Manual terrain deltas and depletion ids live outside `WorldState`.
- Save/load applies owner imports incrementally and is non-transactional.
- Importing changed generation configuration into a live scene can produce a mixed world until already-loaded chunks are rebuilt through streaming.
- Reachability is synchronous, bounded, orthogonal, and limited to loaded cells; it has no caching, async execution, off-screen routing, or terrain-cost model.
- Candidate collection evaluates at most 16 stable-id-ordered records per implemented work type, so later records can be deferred and haul selection can require two path queries per candidate.
- Persistent colonist records live directly on scene nodes.
- `ChunkManager` has broad responsibility across streaming, deltas, live resource indexing, and projections.
- Clock pause/scale does not pause or scale colonist movement, needs, or work.
- Code-backed generation rules, terrain/resource ids, densities, yields, and definitions can affect reconstruction of older version-2 saves without a separate content-version marker.

## Rules For Future Milestones

- Every milestone must identify data ownership, mutation authority, readers, presentation, and persistence responsibility before implementation.
- Invalid actions must not mutate authoritative state.
- Any save-boundary change must update `docs/SAVE_BOUNDARY.md`.
- Any architecture-changing milestone must update `PROJECT_ARCHITECTURE.md` and `CURRENT_BASELINE.md`.
- Prefer focused validation harnesses before adding user-facing UI for a system.
- Do not expand `WorldState` unless a concrete authority or persistence boundary requires it.
- Do not split `ChunkManager` until a concrete pressure justifies the split.
- Do not introduce a shared job board until multiple job types require shared semantics beyond the current focused APIs.
- Working code is insufficient when ownership or simulation authority is unclear.

## Consequences

- Near-term milestones can build on the current owners without first restructuring the project.
- Temporary risks remain visible and bounded rather than being silently treated as permanent design.
- Features that cross current boundaries must justify and document the ownership change before implementation.
- Further save/load, navigation, and resource-authority improvements require explicit milestones rather than incidental refactors.
- Validation must check authoritative state transitions and exclusions, not only visible gameplay behavior.

## Follow-Up Candidates

- `R1 Ground Item Stack/Filter Contract`
- `C1 Simulation Tick And Pause Integration`
