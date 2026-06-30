# ADR A02 — Storage Authority Migration Complete

## Status

Accepted

## Date

2026-06-30

## Context

The original storage model represented the colony's inventory as one global `ResourceStockpile`. Resources were abstract colony-wide totals constrained by shared capacity. Player-created stockpile zones supplied hauling destinations, but the zones did not own their contents or capacity; deposits ultimately mutated the same global inventory.

That model was sufficient for bootstrap gameplay, but it coupled hauling, construction, eating, capacity, and resource display to one shared authority. It could not naturally represent multiple independent stores, local availability, building-specific rules, specialised storage, permissions, priorities, or material requests from workshops. A resource had no meaningful storage location after deposit.

Milestones R02A through R02G migrated active storage gameplay in bounded stages:

- R02A introduced the completed Storehouse and definition-driven storage capacity.
- R02B introduced building-linked storage component records owned by `WorldState`.
- R02C routed hauling reservations and deposits into Storehouse components.
- R02D routed construction reservations and material consumption through Storehouse contents.
- R02E routed eating through Storehouse Food.
- R02F removed stockpile-zone creation from the player-facing workflow while retaining compatibility data.
- R02G ended normal fallback to legacy zones and legacy totals after Storehouse storage becomes available.

## Decision

Completed Storehouse storage components are the gameplay authority for stored resources. Storage is a capability conferred by a completed building definition, not a colony-wide inventory service and not state owned by a scene node.

`WorldState` owns storage component identity, contents, capacity, reservations, validation, and mutation. Components are linked to their completed construction records. Multiple Storehouses therefore remain distinct even when aggregate APIs present colony-wide totals.

Active gameplay follows these rules:

- Hauling reserves capacity and deposits resources into a specific Storehouse component.
- Construction reserves and consumes materials from Storehouse contents once storage exists.
- Eating consumes Food from Storehouse contents once storage exists.
- Storehouse inspection reads defensive storage component snapshots.
- Colonists may request work and transiently carry a ground item, but never own stored resources or storage authority.
- UI owns selection and formatting only; it does not own or mutate storage state.
- Rendering and chunk projections are reconstructible views and are never authoritative.

When any completed storage component exists, active hauling does not fall back to legacy stockpile zones because a Storehouse is full or temporarily unreachable. Worker and direct construction progress, and eating, likewise do not fall back to legacy totals after Storehouse storage becomes authoritative.

## Compatibility

The following legacy behaviour is intentionally retained:

- **Bootstrap construction:** Before the first Storehouse exists, legacy `ResourceStockpile` totals may fund construction. Without this path, a new colony could not create its first authoritative storage building.
- **Legacy version-2 saves:** Version-2 `stockpile` totals and completed construction records continue to load without a schema or version change. Storehouse components are rebuilt from completed construction records, including their persisted `storage_contents`.
- **Aggregate resource APIs:** `get_resource_total()`, resource-total dictionaries, and aggregate UI counters continue to combine compatibility totals with Storehouse contents. Existing readers do not need to understand component layout.
- **Legacy validator support:** Focused legacy and bootstrap APIs remain available where existing validation fixtures require them. These APIs are compatibility surfaces, not the preferred active gameplay path.
- **Legacy stockpile-zone loading:** Zone import/export and save fields remain supported. Zones can still serve the no-Storehouse compatibility path, but they are no longer player-created through the normal UI and are not fallback destinations after Storehouse activation.
- **Compatibility capacity:** The code-backed base capacity and imported legacy totals remain intact so old saves are not truncated or silently redistributed.

These paths remain to preserve existing saves, permit first-Storehouse bootstrap, and avoid an unrelated save migration. They do not establish shared ownership with Storehouse components.

## Consequences

- Multiple Storehouses can hold independent contents and enforce independent capacity.
- Storage identity and location are available for local logistics and distance-aware work.
- Future specialised storage can be expressed as building capabilities instead of global exceptions.
- Workshops can request materials from explicit storage components.
- Food distribution can reason about actual storage locations.
- Simulation systems depend on `WorldState` storage APIs rather than a mutable global inventory.
- UI and rendering remain replaceable projections with no gameplay authority.
- Ownership, reservation, mutation, and persistence boundaries are explicit.
- Legacy totals can coexist with Storehouse contents in old saves, so aggregate reads must continue to avoid transfer or duplication.

## Deferred Work

- Storage filters and accepted-resource rules.
- Storage priorities and hauling preferences.
- Richer storage inspection and logistics UI.
- Workshop material requests and delivery planning.
- Food distribution and meal logistics.
- Storage permissions and access control.
- Storehouse-to-Storehouse transfer work.
- A versioned save migration that converts or retires compatibility totals and zones.
- Final removal of `ResourceStockpile` after bootstrap and save compatibility are migrated.

## Ownership Summary

| System | Owner |
|---|---|
| Storage contents | `WorldState` |
| Storage capacity | `WorldState` |
| Storage reservations | `WorldState` |
| Hauling | `Colonist` requests / `WorldState` authority |
| Construction reservations | `WorldState` |
| Eating | `WorldState` |
| UI | Read-only |
| Rendering | Projection only |

`ResourceStockpile` remains a child compatibility service owned and coordinated by `WorldState`; it is not a second active storage authority.

## Architecture Rules

- Buildings provide capabilities; completed building state determines whether a capability exists.
- Simulation authorities own gameplay records and validate every mutation.
- `WorldState` is the sole storage authority.
- Colonists request storage-related work but do not own stored inventory.
- UI owns interaction and transient selection only.
- Rendering owns visuals only and must be reconstructible from authoritative state.
- Saves persist authoritative state, not UI, reservations, caches, or rendered nodes.
- Derived storage components and capacity must be rebuilt from authoritative completed-building records where specified by the save contract.
- Compatibility paths must remain explicit, bounded, and subordinate to the Storehouse path.
- Avoid shared ownership: one record has one mutation authority.

## Validation

The R02A–R02G focused validators established the implemented storage behavior, including component ownership, Storehouse hauling, construction and eating consumption, inspector reads, zone deprecation, compatibility loading, aggregate totals, and duplication prevention.

This ADR is documentation-only. Its change is validated with repository diff checks; it introduces no runtime, validator, or save-data change.
