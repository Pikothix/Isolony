# Procedural Creature Research B

## Purpose and ownership

This is an isolated procedural-creature presentation experiment. `CreatureDefinition` owns immutable authored constraints; `CreatureGenomeGenerator` owns normal deterministic generation; `CreatureGenome` owns generated presentation values; `DiagnosticCreatureFactory` owns prototype-only bounded edge cases; `CreatureRig` owns semantic anchors and deterministic presentation motion; `ProceduralCreatureVisual` owns reconstructible geometry, draw order, and diagnostic projection; and `CreatureGallery` owns transient test interaction.

The presentation remains reproducible from `definition + seed`. Diagnostic genomes are deliberately authored test inputs rather than production identities. Generated polygons and nodes are ephemeral and must not be save data.

## Procedural motion research

Motion introduces one isolated presentation boundary: `CreatureRig` samples semantic pose data from genome, seed, elapsed time, selected gait, and speed; `ProceduralCreatureVisual` renders that sample. The rig is a `RefCounted` presentation helper with no nodes, physics, simulation position, AI, or gameplay authority.

Idle motion combines tiny torso-height and chest-depth breathing changes, compensated head motion, fixed-foot front/rear weight transfer, delayed tail response, and sub-pixel ear reaction. The renderer never scales the creature node.

Walking is a single loop derived from one gait phase. Near-front/far-rear limbs share a phase, with far-front/near-rear offset by `PI`. Swing feet lift and advance; stance feet stay at their authored targets because the prototype body does not translate. Body bob, stabilized head response, tail lag, and ear motion all derive from the same phase.

Tail motion is an analytic damped-response approximation: the root follows the body immediately while midpoint and tip use an attenuated, phase-lagged drive. It deliberately avoids physics and accumulated solver state, making samples reproducible at any requested time.

Gallery controls select Idle, Treadmill Walk, or Planted Walk, pause elapsed presentation time, reset locomotion, and adjust gait speed from 0.25× to 2×. Normal, Silhouette, and Depth Layers animate. Anchors stays static for Idle/Treadmill but exposes live planted-foot state in Planted Walk.

## Planted-foot model

`Planted Walk` advances a presentation-only root continuously to the right on a flat baseline. The visual node stays centred; a scrolling tick lane exposes travel. Every stance foot stores an immutable presentation-world position while the root advances, and the rig converts it back for rendering with `local_x = foot_world_x - root_world_x`.

Each explicit foot follows `STANCE → LIFT → SWING → PLANT`:

- **STANCE** retains its exact world position while the root advances.
- **LIFT** raises the foot with minimal early horizontal travel.
- **SWING** uses smooth interpolation and a bounded arc toward a target chosen once at lift entry.
- **PLANT** descends smoothly and finishes exactly at the stored target before returning to stance.

Near-front/far-rear form pair A; far-front/near-rear form pair B at half-cycle offset. A target combines the predicted root position at plant completion, the authored preferred local foot position, and bounded stride lead. It is never recomputed during the step.

## Determinism policy

Live planted locomotion uses an internal `1/60` second timestep and an accumulator capped at 240 internal steps per update. Variable render deltas only contribute time to that accumulator; state transitions, root travel, and foot trajectories advance exclusively on fixed steps.

`reset_locomotion()` clears root position, gait time, accumulator, every foot state, planted/start/target positions, and transient pose output. Switching into Planted Walk, changing its speed, rebuilding specimens, or pressing Reset Locomotion establishes the same coherent starting stance.

Fixed-time planted sampling creates a fresh rig and replays whole fixed steps from time zero. Validation compares only fixed-step-aligned durations. Equivalent totals using 60 × 1/60, 30 × 1/30, and mixed 0.01/0.04 deltas produce identical snapshots.

Anchor diagnostics expose root travel, preferred local feet, actual local feet, target positions, and all four foot-state labels. Blue markers are preferred positions and orange markers are targets.

## Planted-walk findings

Automated presentation-coordinate checks confirm that stance positions remain fixed, planting reaches targets exactly, diagonal roles remain synchronized, and fixed-step trajectories contain no large discontinuity. The scrolling baseline makes visual sliding inspectable. Manual review is still required before claiming the lift/plant timing feels natural, the body appears supported, or secondary head/tail motion improves the translated gait. The former mechanically placed knees motivated the focused flat-ground IK refinement below.

## Two-bone leg model

`TwoBoneIK` is a small pure solver owned by the experimental presentation layer. It accepts hip, authoritative foot target, upper/lower segment lengths, and an explicit bend sign. It returns the solved knee, original and clamped targets, reachability, validity, minimum/maximum reach, extension ratio, and segment lengths.

The rig derives total reach from authored leg length plus a small body-height allowance for the embedded hip. Lean bodies use a 47/53 upper/lower split, stocky bodies use 53/47, and other profiles use 50/50. No additional genome parameters were introduced.

Front legs bend rearward and rear legs bend forward in the existing right-facing side view. Near and far legs retain their established hip offsets and depth order. The renderer draws only the rig-provided hip, knee, and clamped endpoint, adds a small overlapping joint cap, and marks any bounded reach correction to the authoritative foot.

Reach uses `abs(upper - lower)` through `upper + lower`. Overextended and too-close targets clamp along the hip-to-foot direction. Zero-distance input uses a stable downward direction; invalid or non-finite input returns a finite fallback pose with `valid = false`. Solver inputs remain sub-pixel and only final drawing is pixel-snapped.

## IK and locomotion interaction

The planted-foot state machine remains unchanged and continues to own actual foot positions. IK derives only the intermediate knee and never rewrites planted world positions, swing targets, root translation, or foot states. A reach audit across 2,208 normal/extreme gait samples produced 2 bounded clamps (about 0.09%), so no stride, timing, target-lead, or body-bob retuning was justified.

Anchor diagnostics show solved knees, segment lines, extension ratios, and red clamp indicators. Coordinate validation confirms deterministic segment lengths and bend signs. Manual review is still required to determine whether articulation reads naturally, whether compact profiles collapse, whether thin limbs survive at 1×, and whether the gait remains mechanically phased despite improved joints.

## Refined leg presentation

The renderer converts each solved IK chain into two four-point tapered polygons. Upper segments are broader where they enter the body and narrow toward the knee. Lower segments overlap the upper segment at the solved knee, taper toward the foot, and extend slightly into the foot connection. A small bridge is drawn beneath both overlapping polygons, so it cannot read as a detached decorative kneecap.

Front legs use a slightly narrower knee and lower endpoint for a straighter silhouette. Rear legs retain more width through the knee and foot for a subtly stronger angled silhouette. Segment widths use a 1.5-pixel presentation minimum derived only at render time; genome thickness is unchanged. This protects thin limbs at 1× while keeping far/near depth colours intact.

Feet are compact four-point horizontal pads. Front pads are slightly shorter than rear pads, remain attached to the authoritative foot endpoint, and never rotate during stance. The renderer therefore cannot introduce world-space stance drift or contact reorientation.

The existing analytic contact curves were retained after review: lift begins with only eight percent of target travel while rising, swing uses smoothstep horizontal motion with a bounded arc, and plant smooths both horizontal descent and height to the exact target. No bend magnitude, fixed-step timing, state sequence, body bob, stride, target, or planted-position changes were required.

Coordinate validation continues to pass for all normal/extreme samples with the same 2/2,208 clamp count. Manual review remains authoritative for knee continuity, foot contact, thin-leg survival, compact-profile collapse, front/rear distinction, and whether the gait still feels mechanical.

## Facing projection

`CreatureFacingProjection` is a pure boundary between direction-agnostic rig poses and the procedural renderer. Rig `x` is treated as forward travel and rig `y` as vertical height. The projection adds a bounded presentation-only lateral offset for near/far anatomy, then maps forward motion diagonally into screen `x/y` while leaving vertical height vertical.

Supported values are `NE`, `SE`, `SW`, and `NW`. NE/SE share positive screen-x travel and SW/NW mirror that component. North facings travel upward on screen; south facings travel downward. This bounded mirroring is used only for the forward basis. Near/far legs, ear strength, eye visibility, tail depth, and draw metadata are still explicitly resolved per facing.

NE and SW retain the rig's near/far source roles. SE and NW swap semantic near/far sources before projection. Every output exposes unique `near_front`, `far_front`, `near_rear`, and `far_rear` mappings plus an explicit order: far rear, far front, rearward tail, body, near rear, near front, head, attachments.

South-facing projections place the tail behind the body because the rear points away on screen; north-facing projections draw it after the body because the rear is closer. One near eye is rendered fully. The far eye is omitted, the far ear is reduced, and the near ear retains full strength.

Apparent torso length is compressed to 82 percent and body masses are constructed along the projected forward basis rather than rotating a completed flat sprite. Shoulder, hip, neck, head, muzzle, tail, every hip/knee/foot chain, and diagnostic anchors are projected independently. No genome values change.

## Four-facing identity

Body profile, dimensions, taper, chest/hip balance, head and muzzle size, ear profile, tail length, palette, posture, and leg dimensions remain shared because all panels reference one genome. Length and taper are less visually explicit after isometric compression; ear profile, tail length, palette, and head/body ratio should remain the strongest identity cues.

The gallery can show one selected facing for focused motion or one genome in all four facings. Four-facing panels start from equivalent rig state and receive the same gait, speed, pause, reset, diagnostic mode, and scale selection. Deterministic pose sampling prevents facing-specific phase changes.

## Four-facing locomotion findings

Planted world coordinates and foot states remain unchanged in semantic rig space. Projection maps root travel, stance feet, swing targets, and solved IK points into the selected diagonal direction. The centred lane scrolls opposite the projected travel basis so apparent stance drift remains inspectable.

Automated checks confirm finite deterministic projections, complete role mappings, preserved gait state, attached tails, and non-collapsed projected IK segments. Manual review is still required for apparent foot planting, diagonal-pair readability, knee reversal, silhouette overlap, and whether north-facing tail/head ordering is convincing.

## Renderer viability finding

The semantic genome, rig, planted-foot model, IK, and facing projection remain viable presentation research boundaries. The procedural polygon renderer is useful for diagnostics but should not yet be treated as a production art solution. Four-way compressed masses, one-pixel facial details, and overlapping projected limbs are likely to benefit from authored modular directional sprites driven by the same semantic rig.

## Modular sprite renderer

`ModularCreatureSpriteRenderer` is a parallel, presentation-only consumer of the same genome and projected pose used by `ProceduralCreatureVisual`. It owns 20 `Sprite2D` part nodes, texture selection, explicit pivots, transforms, modulation, mirroring, and depth. It owns no rig, gait timer, foot state, IK solve, facing authority, or simulation position.

`ModularCreatureSpriteSet` is an immutable Resource containing two authored directional dictionaries (`north_oblique` and `south_oblique`), normalized attachment pivots, default scales, and depth biases. Each set contains body, head, front/rear upper and lower legs, foot, three ear profiles, three tail segments, and shadow. The genome never stores texture paths.

The research assets were generated with the built-in image-generation path as two neutral grayscale 4×4 chroma-key source sheets, keyed locally to alpha, cropped into 28 individual hard-edged PNG parts, and resized with nearest-neighbour sampling. Final project parts live under `assets/modular_quadruped/north_oblique/` and `south_oblique/`; source sheets are retained under `assets/modular_quadruped/sources/` for provenance. The prompt requested minimal crisp pixel art, consistent upper-left lighting, isolated parts, no text, and a uniform `#00ff00` removable background.

North facings select the north-oblique set and south facings select the south-oblique set. NW and SW mirror authored textures horizontally; semantic near/far role reassignment still comes from `CreatureFacingProjection` and is not replaced by mirroring.

Body scaling is bounded to 0.8–1.25 horizontally and 0.85–1.2 vertically. Head scaling is bounded to 0.82–1.18. Limb sprites pivot at hip or knee, rotate toward the next semantic point, and scale primarily along their authored vertical length axis. Feet remain centered on authoritative endpoints. Three horizontal-pivot tail sprites follow root, midpoint, and tip. Ear profile selects the matching authored texture, with reduced far-ear modulation.

The gallery offers Procedural Polygons, Modular Sprites, and Side-by-Side. Both renderers are instantiated only when needed, share one pose-producing visual, genome, facing, gait, speed, pause state, and scale, and renderer switching changes visibility/layout without rebuilding or resetting locomotion. Four-facing comparison supports either renderer and uses one genome in all panels.

Modular diagnostics support Normal, Depth Layers, and Anchors. Other requested gallery modes fall back to Normal for the modular renderer while remaining fully available on polygons.

## Modular comparison findings

Automated validation confirms complete assets and pivots, finite transforms, exact hip/knee/foot sprite origins, connected tail starts, deterministic two-set mirroring, correct ear selection, genome non-mutation, and preserved gait phase during renderer switching. A modular creature uses 20 sprite nodes plus its renderer root (21 nodes), compared with one procedural `CanvasItem` node. The validator prints measured 12-creature construction time and 120 modular pose-update time for the current machine; these are prototype proxies, not production-scale performance claims.

Authored contours should improve body, head, ear, and foot recognition at 1×, but generated source parts include stronger internal modelling than a final restricted palette would likely use. Length scaling of limb and tail parts can reveal pixel repetition, and mirrored highlights may expose the two-set experiment. Palette modulation preserves colour identity, while body/head scale, ear choice, tail chain, leg thickness, and posture retain procedural variation.

Manual side-by-side review remains authoritative for whether modular sprites materially beat polygons, whether north/south sets mirror acceptably, whether all four facings preserve identity, and whether IK articulation looks coherent with authored segment contours.

## Production direction

For this research milestone, modular directional sprites are the preferred candidate renderer because they preserve the renderer-independent semantic rig while offering controlled silhouettes. This is not production promotion: the two-set mirroring experiment, authored palette discipline, pivot tuning, and game-scale visual review must pass before deciding whether two or four complete directional sets are required.

## Organic body outline

The procedural polygon renderer now derives one closed 14-point body polygon instead of composing its silhouette from a torso polygon plus overlapping shoulder, hip, and neck ellipses. Ordered semantic regions cover rear upper back, mid-back, front upper back, upper neck, forward neck, lower neck, shoulder/chest front, lower chest, front belly, mid belly, rear belly, lower hip, rear rump, and upper rump.

No generic spline or mesh framework is used. Points are derived explicitly from genome dimensions and projected anchors, retained at sub-pixel precision, normalized to clockwise winding, and passed directly to `draw_colored_polygon`. The compact outline needs no subdivision; avoiding a smoothing pass preserves authored region intent and prevents extra points at 1×.

Existing body length, height, taper, chest depth, hip volume, body profile, posture, facing compression, body/head anchors, and projected forward basis remain the main inputs. Five independently salted cosmetic values add bounded subtle variation without perturbing the primary RNG sequence:

- `back_curve` (`-0.12…0.12`) adjusts arch or dip.
- `belly_curve` (`-0.12…0.16`) adjusts tuck or fullness.
- `shoulder_slope` (`-0.10…0.12`) adjusts upper-back-to-neck transition.
- `rump_slope` (`-0.10…0.12`) adjusts upper hip and tail-root contour.
- `neck_thickness` (`0.65…1.15`) adjusts the body-to-head bridge.

The salted outline RNG uses `seed ^ 0x5a17c9e3` after all primary generation. Adding these values changes genome debug summaries but leaves pre-existing dimensions, palettes, ears, tails, profiles, postures, and locomotion traits stable.

All profiles share the same topology. Lean adds belly tuck; Neutral uses unmodified balanced curves; Stocky increases belly fullness; Heavy Front strengthens the shoulder/neck transition through its existing chest mass and a bounded shoulder adjustment; Heavy Rear strengthens the rump through existing hip volume and a bounded rump adjustment. Alert straightens the back and lifts the shoulder line, Curious extends the shoulder subtly, Relaxed softens back and belly, and Proud raises the shoulder/neck transition.

Upper and lower neck points extend toward the projected head anchor so the separately rendered head overlaps one coherent body boundary. Front and rear body regions cover the projected hip anchors with bounded tolerance, allowing upper leg sprites/polygons to disappear into the fill. Rear rump points remain close to the projected tail root without moving the tail or rig.

Silhouette uses the same final outline as Normal. Depth Layers substitutes only body colour. Neutral Palette preserves identical points. Anchors labels every second body control point (`b0`, `b2`, …) for concise contour inspection.

The focused audit covers 32 deterministic seeds plus 14 extreme genomes in all four facings: 184 outlines. Every result has 14 finite points, clockwise winding, no self-intersections, non-collapsed bounds, and valid head, tail, and hip attachment proximity. Locomotion, IK, planted feet, facing projection, and the modular renderer are unchanged.

Strong expected results are Lean and Heavy Front, where the continuous back/neck line and tucked underside provide clear direction. Stocky remains the highest risk for belly/leg merging, and compact Heavy Rear variants remain at risk of appearing round. Manual review is required to confirm that overlapping-mass artefacts are materially reduced, silhouettes improve at 1×, and the outline stays coherent during motion.

Further outline complexity is not currently justified. Species archetypes, coat markings, new limb systems, locomotion redesign, production integration, saved polygon points, and production art commitments remain explicitly excluded.

## Shape language

The torso is no longer a single ellipse. It combines a bounded tapered torso polygon with overlapping shoulder, hip, and neck masses. All profiles retain the same quadruped topology and semantic anchors.

- **Lean** favours a long-looking, shallow torso, reduced hip mass, and mild front-to-rear taper.
- **Neutral** retains balanced shoulder and hip volume with restrained random taper.
- **Stocky** deepens both chest and hip masses and widens the stance.
- **Heavy Front** emphasizes the shoulder/chest mass and tapers toward a smaller rear.
- **Heavy Rear** emphasizes the hip mass and narrows toward the shoulder.

Generated `torso_taper`, `chest_depth`, `hip_volume`, `stance_width`, and subtle `muzzle_length` values remain bounded by the authored definition or a small fixed detail range.

## Posture presets

- **Neutral** keeps a level head and tail.
- **Alert** raises the head and tail.
- **Curious** reaches the head forward with a nearly level tail.
- **Relaxed** lowers the head and tail.
- **Proud** raises the chest-facing head and carries the tail highest.

Posture changes anchor projection only. It is not mutable pose or animation state.

## Diagnostic modes

- **Normal** shows generated palettes and details.
- **Silhouette** removes internal details and projects anatomy in one solid colour to expose outline failures.
- **Depth Layers** colours far legs, body, near legs, head, and attachments separately to expose occlusion and draw order.
- **Anchors** overlays body/head anchors, front/rear hips, four explicit foot targets, tail root, and ground baseline.
- **Neutral Palette** preserves geometry while replacing generated colours with one restrained palette.

The gallery selector switches between 12 consecutive deterministic seeds and 14 explicit bounded extreme specimens. The game-scale toggle renders at 1× over a non-authoritative 32×16 isometric ground diamond and a 16-pixel height marker; normal inspection uses 2× scale.

## Static-pose findings and changes

The strongest expected silhouettes are lean/alert and heavy-front/proud combinations because their mass direction and head carriage reinforce one another. Neutral remains the safest general profile. Stocky/relaxed can compress the leg/body separation, while heavy-rear with a small head can make the neck transition weak. The overlapping neck mass removes the obvious detached-head gap, and raised hips let legs disappear into shoulder and hip volume.

Prototype A's near/far feet could converge around compact bodies and the tail was drawn before all legs rather than in the documented anatomy order. The current pose gives all four legs explicit hip and foot roles, spreads foot targets using deterministic stance width, offsets far feet upward/inward and near feet outward, and groups drawing as shadow → far legs → tail → body masses → near legs → head/details. Ear roots overlap the skull more deeply and tail angle follows posture.

Ears and tail now share attachment colouring in Depth Layers. Long and pointed ears are shortened for heads of eight pixels or less. Pixel snapping strengthens hard-edged diagnostic comparison, but small diagonal legs and ears can still become visually uneven at 1×. Thick, short legs remain the most likely anatomy to merge with the body; large heads on short bodies remain deliberately weak extreme cases.

Manual rendered review is still authoritative for silhouette coherence, attachment quality, pixel-art suitability, and scale readability. The implementation does not claim those reviews have passed.

## Constraint changes

- Normal-generation tail maximum is capped at `body length - 6`, within the authored tail range, so the smallest bodies cannot receive the longest tail.
- Existing long-body head-size restriction remains unchanged.
- Existing taller-body minimum leg-thickness rule remains unchanged.
- Static ear geometry reduces long/pointed ear reach on very small heads; this is rendering projection, not genome mutation.
- Foot spacing now scales from body length in the static pose.
- Body profile applies bounded chest, hip, taper, and stance dependencies before posture selection.
- Stocky and heavy-front bodies require at least the second leg-thickness tier.
- Posture deterministically selects head and tail anchor offsets without changing anatomy.

## Scale findings

The 1× view makes the body silhouette and four-foot baseline inspectable against a 32×16 cell. Eyes are only about one pixel and articulated leg bends can compress, so detail survival is uncertain until manual review. The current creatures are broadly one cell wide before tails, with tall variants exceeding the 16-pixel reference height because legs and body stack vertically.

## Running and validation

Run `CreatureGallery.tscn` directly. For scoped data validation, run:

```text
godot --headless --path . --script res://experimental/procedural_creature_research/prototype_validation.gd
```

## Explicit exclusions and promotion criteria

IK, skeletal animation, terrain adaptation, slopes, state machines, turning, directional facings, simulation integration, creature AI, navigation, collision, physics, world spawning, persistence integration, production movement, and production promotion are excluded.

Do not promote this prototype until it passes static silhouette review, game-scale readability review, four-direction presentation research, procedural-animation research, and runtime cost measurement. None of those gates is claimed complete here.
