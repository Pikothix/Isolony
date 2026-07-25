extends SceneTree

## Small scoped validation for deterministic data, diagnostic projection, and bounds.

const DEFINITION := preload("res://experimental/procedural_creature_research/definitions/small_quadruped.tres")
const GenomeGenerator := preload("res://experimental/procedural_creature_research/creature_genome_generator.gd")
const CreatureVisual := preload("res://experimental/procedural_creature_research/procedural_creature_visual.gd")
const DiagnosticFactory := preload("res://experimental/procedural_creature_research/diagnostic_creature_factory.gd")
const GalleryScene := preload("res://experimental/procedural_creature_research/CreatureGallery.tscn")
const RigScript := preload("res://experimental/procedural_creature_research/creature_rig.gd")
const TwoBoneIKScript := preload("res://experimental/procedural_creature_research/two_bone_ik.gd")
const FacingProjection := preload("res://experimental/procedural_creature_research/creature_facing_projection.gd")
const ModularRenderer := preload("res://experimental/procedural_creature_research/modular_creature_sprite_renderer.gd")
const SPRITE_SET := preload("res://experimental/procedural_creature_research/definitions/small_quadruped_sprite_set.tres")


func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []
	var first: Resource = GenomeGenerator.generate(DEFINITION, 1000)
	var repeat: Resource = GenomeGenerator.generate(DEFINITION, 1000)
	if first == null or repeat == null or first.debug_summary() != repeat.debug_summary():
		failures.append("normal generation is not deterministic")
	var original_summary: String = first.debug_summary() if first != null else ""
	if first != null:
		for mode: String in CreatureVisual.SUPPORTED_MODES:
			var visual: Node2D = CreatureVisual.new()
			get_root().add_child(visual)
			visual.configure(first, mode)
			var anchors: Dictionary = visual.get_semantic_points()
			for required: String in ["body_anchor", "head_anchor", "front_hip", "rear_hip", "near_front_foot", "near_rear_foot", "far_front_foot", "far_rear_foot", "tail_root", "ground_y"]:
				if not anchors.has(required):
					failures.append("%s missing anchor %s" % [mode, required])
			visual.queue_free()
		if first.debug_summary() != original_summary:
			failures.append("diagnostic projection mutated the genome")
	var specimens: Array[Dictionary] = DiagnosticFactory.create_specimens(DEFINITION)
	if specimens.size() < 14:
		failures.append("expected at least 14 controlled specimens")
	for specimen: Dictionary in specimens:
		if not DiagnosticFactory.is_within_bounds(specimen.genome, DEFINITION):
			failures.append("out-of-bounds specimen: %s" % specimen.label)
	var observed_profiles := {}
	var observed_postures := {}
	for seed in range(256):
		var audited: Resource = GenomeGenerator.generate(DEFINITION, seed)
		if not DiagnosticFactory.is_within_bounds(audited, DEFINITION):
			failures.append("out-of-bounds generated seed: %d" % seed)
			break
		observed_profiles[String(audited.body_profile)] = true
		observed_postures[String(audited.posture)] = true
	if observed_profiles.size() != DEFINITION.body_profiles.size():
		failures.append("seed audit did not cover every body profile")
	if observed_postures.size() != DEFINITION.posture_profiles.size():
		failures.append("seed audit did not cover every posture")
	var rig_a := RigScript.new(first)
	var rig_b := RigScript.new(repeat)
	for gait: String in [RigScript.GAIT_IDLE, RigScript.GAIT_WALKING]:
		for sample_time: float in [0.0, 0.25, 0.75, 1.5]:
			if JSON.stringify(rig_a.sample(sample_time, gait, 1.0)) != JSON.stringify(rig_b.sample(sample_time, gait, 1.0)):
				failures.append("animation sample is not reproducible: %s %.2f" % [gait, sample_time])
	_validate_planted_walk(first, failures)
	_validate_two_bone_solver(failures)
	_validate_ik_coverage(specimens, failures)
	_validate_facing_projection(first, failures)
	_validate_body_outlines(specimens, failures)
	await _validate_modular_renderer(first, failures)
	var gallery: Control = GalleryScene.instantiate()
	get_root().add_child(gallery)
	await process_frame
	var mode_selector: OptionButton = gallery.get_node("Diagnostics/ModeSelector")
	for mode_index in range(mode_selector.item_count):
		mode_selector.select(mode_index)
		mode_selector.item_selected.emit(mode_index)
		await process_frame
	var gallery_selector: OptionButton = gallery.get_node("Diagnostics/GallerySelector")
	gallery_selector.select(1)
	gallery_selector.item_selected.emit(1)
	var scale_toggle: CheckButton = gallery.get_node("Diagnostics/GameScaleToggle")
	scale_toggle.button_pressed = true
	scale_toggle.toggled.emit(true)
	await process_frame
	var facing_selector: OptionButton = gallery.get_node("Diagnostics/FacingSelector")
	for facing_index in range(facing_selector.item_count):
		facing_selector.select(facing_index)
		facing_selector.item_selected.emit(facing_index)
		for mode_index in range(mode_selector.item_count):
			mode_selector.select(mode_index)
			mode_selector.item_selected.emit(mode_index)
			await process_frame
	var four_facing_toggle: CheckButton = gallery.get_node("Diagnostics/FourFacingToggle")
	four_facing_toggle.button_pressed = true
	four_facing_toggle.toggled.emit(true)
	await process_frame
	var comparison_summaries := {}
	var comparison_root_positions := {}
	for cell in gallery.get_node("Gallery").get_children():
		for child in cell.get_children():
			if child.has_method("get_genome_summary"):
				comparison_summaries[child.get_genome_summary()] = true
				var comparison_pose: Dictionary = child.sample_pose(1.0, RigScript.GAIT_PLANTED, 1.0)
				comparison_root_positions[snappedf(comparison_pose.root_world_x, 0.000001)] = true
	if comparison_summaries.size() != 1:
		failures.append("four-facing comparison does not share one genome")
	if comparison_root_positions.size() != 1:
		failures.append("four-facing comparison is not phase-synchronised")
	var renderer_selector: OptionButton = gallery.get_node("RendererControls/RendererSelector")
	var pause_button: CheckButton = gallery.get_node("Motion/PauseButton")
	pause_button.button_pressed = true
	pause_button.toggled.emit(true)
	await process_frame
	var phase_before: float = _first_gallery_root_phase(gallery)
	for renderer_index in range(renderer_selector.item_count):
		renderer_selector.select(renderer_index)
		renderer_selector.item_selected.emit(renderer_index)
		await process_frame
	if not is_equal_approx(phase_before, _first_gallery_root_phase(gallery)):
		failures.append("renderer switching reset or advanced shared gait phase")
	gallery.get_node("Motion/WalkingButton").pressed.emit()
	var speed_slider: HSlider = gallery.get_node("Motion/SpeedSlider")
	speed_slider.value = 1.4
	speed_slider.value_changed.emit(1.4)
	pause_button.button_pressed = true
	pause_button.toggled.emit(true)
	await process_frame
	pause_button.button_pressed = false
	pause_button.toggled.emit(false)
	gallery.get_node("Motion/PlantedButton").pressed.emit()
	gallery.get_node("Motion/ResetLocomotionButton").pressed.emit()
	await process_frame
	gallery.queue_free()
	if failures.is_empty():
		print("CREATURE_PROTOTYPE_VALIDATION PASS modes=%d extremes=%d profiles=%d postures=%d" % [CreatureVisual.SUPPORTED_MODES.size(), specimens.size(), observed_profiles.size(), observed_postures.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _validate_planted_walk(genome: Resource, failures: Array[String]) -> void:
	var replay_a := RigScript.new(genome)
	var replay_b := RigScript.new(genome)
	var fixed_a: Dictionary = replay_a.sample_planted_snapshot(2.0, 1.0)
	var fixed_b: Dictionary = replay_b.sample_planted_snapshot(2.0, 1.0)
	if JSON.stringify(fixed_a) != JSON.stringify(fixed_b):
		failures.append("planted fixed-time replay is not deterministic")

	var sixty := RigScript.new(genome)
	var thirty := RigScript.new(genome)
	var mixed := RigScript.new(genome)
	for _index in range(60): sixty.advance_locomotion(1.0 / 60.0, 1.0)
	for _index in range(30): thirty.advance_locomotion(1.0 / 30.0, 1.0)
	for _index in range(20):
		mixed.advance_locomotion(0.01, 1.0)
		mixed.advance_locomotion(0.04, 1.0)
	var sixty_snapshot: String = JSON.stringify(sixty.get_locomotion_snapshot())
	if sixty_snapshot != JSON.stringify(thirty.get_locomotion_snapshot()) or sixty_snapshot != JSON.stringify(mixed.get_locomotion_snapshot()):
		failures.append("fixed-step result differs across equal-total delta sequences")

	var rig := RigScript.new(genome)
	var initial: String = JSON.stringify(rig.get_locomotion_snapshot())
	var previous: Dictionary = rig.get_locomotion_snapshot()
	var exact_plants: int = 0
	for _step in range(240):
		rig.advance_locomotion(RigScript.FIXED_TIMESTEP, 1.0)
		var current: Dictionary = rig.get_locomotion_snapshot()
		if current.root_x < previous.root_x:
			failures.append("planted root motion is not monotonic")
			break
		for foot_key: String in RigScript.FOOT_KEYS:
			var old_foot: Dictionary = previous.feet[foot_key]
			var new_foot: Dictionary = current.feet[foot_key]
			if old_foot.state == RigScript.STATE_STANCE and new_foot.state == RigScript.STATE_STANCE and old_foot.planted_world != new_foot.planted_world:
				failures.append("stance world position drifted: %s" % foot_key)
			if old_foot.state == RigScript.STATE_PLANT and new_foot.state == RigScript.STATE_STANCE:
				exact_plants += 1
				if new_foot.world != new_foot.target_world or new_foot.planted_world != new_foot.target_world:
					failures.append("plant did not finish exactly at target: %s" % foot_key)
			if not Vector2(new_foot.world).is_finite() or absf(new_foot.world.x - current.root_x) > 100.0 or absf(new_foot.world.y) > 20.0:
				failures.append("foot position invalid or unbounded: %s" % foot_key)
			if Vector2(old_foot.world).distance_to(new_foot.world) > 5.0:
				failures.append("foot trajectory is discontinuous: %s" % foot_key)
		if current.feet.near_front.state != current.feet.far_rear.state or current.feet.far_front.state != current.feet.near_rear.state:
			failures.append("diagonal pair coordination diverged")
			break
		previous = current
	var visited: Dictionary = rig.get_visited_states()
	for foot_key: String in RigScript.FOOT_KEYS:
		for state: String in [RigScript.STATE_STANCE, RigScript.STATE_LIFT, RigScript.STATE_SWING, RigScript.STATE_PLANT]:
			if not visited[foot_key].has(state):
				failures.append("%s never visited %s" % [foot_key, state])
	if exact_plants == 0:
		failures.append("no exact plant completions observed")
	rig.reset_locomotion(1.0)
	if JSON.stringify(rig.get_locomotion_snapshot()) != initial:
		failures.append("locomotion reset did not reproduce initial snapshot")


func _validate_two_bone_solver(failures: Array[String]) -> void:
	var reachable: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2(5, 6), 5.0, 5.0, 1.0)
	if not reachable.reachable or not _segments_match(reachable, 0.002):
		failures.append("reachable IK case failed")
	var overextended: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2(20, 0), 5.0, 5.0, 1.0)
	if overextended.reachable or absf(Vector2(overextended.clamped_target).length() - overextended.maximum_reach) > 0.002:
		failures.append("overextended IK target did not clamp to maximum reach")
	var too_close: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2(1, 0), 6.0, 2.0, -1.0)
	if too_close.reachable or absf(Vector2(too_close.clamped_target).length() - too_close.minimum_reach) > 0.002:
		failures.append("too-close IK target did not clamp to minimum reach")
	var zero_distance: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2.ZERO, 4.0, 4.0, 1.0)
	if not _solution_is_finite(zero_distance):
		failures.append("zero-distance IK solution is not finite")
	var invalid: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2(2, 3), -1.0, 0.0, 1.0)
	if invalid.valid or not _solution_is_finite(invalid):
		failures.append("invalid IK input did not fail safely")
	var non_finite: Dictionary = TwoBoneIKScript.solve(Vector2(NAN, 0), Vector2(INF, 3), 4.0, 4.0, 1.0)
	if non_finite.valid or not _solution_is_finite(non_finite):
		failures.append("non-finite IK input did not return a finite fallback")
	var rear_bend: Dictionary = TwoBoneIKScript.solve(Vector2.ZERO, Vector2(2, 8), 5.0, 5.0, -1.0)
	var front_cross: float = Vector2(reachable.target - reachable.root).cross(Vector2(reachable.joint - reachable.root))
	var rear_cross: float = Vector2(rear_bend.target - rear_bend.root).cross(Vector2(rear_bend.joint - rear_bend.root))
	if front_cross <= 0.0 or rear_cross >= 0.0:
		failures.append("IK knee bend direction is inconsistent")
	if JSON.stringify(reachable) != JSON.stringify(TwoBoneIKScript.solve(Vector2.ZERO, Vector2(5, 6), 5.0, 5.0, 1.0)):
		failures.append("repeated IK solve is not deterministic")


func _validate_ik_coverage(specimens: Array[Dictionary], failures: Array[String]) -> void:
	var clamp_count: int = 0
	var solve_count: int = 0
	var genomes: Array[Resource] = []
	for seed in range(32):
		genomes.append(GenomeGenerator.generate(DEFINITION, seed))
	for specimen: Dictionary in specimens:
		genomes.append(specimen.genome)
	for genome: Resource in genomes:
		var rig := RigScript.new(genome)
		for gait: String in [RigScript.GAIT_IDLE, RigScript.GAIT_WALKING, RigScript.GAIT_PLANTED]:
			for sample_time: float in [0.0, 0.25, 0.5, 0.75]:
				var pose: Dictionary = rig.sample(sample_time, gait, 1.0)
				for role: String in RigScript.FOOT_KEYS:
					var solution: Dictionary = pose["%s_ik" % role]
					solve_count += 1
					if solution.clamped:
						clamp_count += 1
					if not _solution_is_finite(solution) or (solution.reachable and not _segments_match(solution, 0.003)):
						failures.append("invalid IK solution for seed %d %s %s" % [genome.seed, gait, role])
						return
	if solve_count > 0 and float(clamp_count) / float(solve_count) > 0.05:
		failures.append("normal/extreme gait IK clamps too frequently: %d/%d" % [clamp_count, solve_count])
	else:
		print("CREATURE_IK_AUDIT clamps=%d solves=%d" % [clamp_count, solve_count])


func _segments_match(solution: Dictionary, tolerance: float) -> bool:
	return absf(Vector2(solution.root).distance_to(solution.joint) - solution.upper_length) <= tolerance \
		and absf(Vector2(solution.joint).distance_to(solution.clamped_target) - solution.lower_length) <= tolerance


func _solution_is_finite(solution: Dictionary) -> bool:
	return Vector2(solution.root).is_finite() and Vector2(solution.joint).is_finite() \
		and Vector2(solution.target).is_finite() and Vector2(solution.clamped_target).is_finite() \
		and is_finite(float(solution.extension_ratio))


func _validate_facing_projection(genome: Resource, failures: Array[String]) -> void:
	var rig := RigScript.new(genome)
	var original_summary: String = genome.debug_summary()
	for gait: String in [RigScript.GAIT_IDLE, RigScript.GAIT_WALKING, RigScript.GAIT_PLANTED]:
		for sample_time: float in [0.0, 0.5, 1.0]:
			var semantic: Dictionary = rig.sample(sample_time, gait, 1.0)
			var reference_states := {}
			for role: String in RigScript.FOOT_KEYS:
				if semantic.has("%s_state" % role): reference_states[role] = semantic["%s_state" % role]
			for facing: String in FacingProjection.FACINGS:
				var projected: Dictionary = FacingProjection.project(semantic, facing)
				if JSON.stringify(projected) != JSON.stringify(FacingProjection.project(semantic, facing)):
					failures.append("facing projection is not deterministic: %s" % facing)
				var mapped_roles: Array = projected.role_source_map.values()
				var unique_roles := {}
				for mapped_role: String in mapped_roles: unique_roles[mapped_role] = true
				if mapped_roles.size() != 4 or unique_roles.size() != 4:
					failures.append("facing role map incomplete: %s" % facing)
				for required: String in ["far_rear", "far_front", "body", "near_rear", "near_front", "head", "attachments"]:
					if required not in projected.draw_order:
						failures.append("facing draw order missing %s: %s" % [required, facing])
				if projected.show_far_eye or projected.near_ear_strength <= projected.far_ear_strength:
					failures.append("facing eye/ear visibility invalid: %s" % facing)
				if Vector2(projected.tail_root).distance_to(projected.body_anchor) > float(genome.body_length):
					failures.append("projected tail root detached: %s" % facing)
				for point_key: String in ["body_anchor", "head_anchor", "tail_root", "tail_mid", "tail_tip", "near_front_foot", "far_front_foot", "near_rear_foot", "far_rear_foot"]:
					if not Vector2(projected[point_key]).is_finite():
						failures.append("non-finite projected point %s: %s" % [point_key, facing])
				for role: String in RigScript.FOOT_KEYS:
					var solution: Dictionary = projected["%s_ik" % role]
					if not _solution_is_finite(solution) or Vector2(solution.root).distance_to(solution.joint) < 0.25 or Vector2(solution.joint).distance_to(solution.clamped_target) < 0.25:
						failures.append("projected IK continuity collapsed: %s %s" % [facing, role])
				if not reference_states.is_empty():
					var projected_states: Array = []
					for role: String in RigScript.FOOT_KEYS: projected_states.append(projected["%s_state" % role])
					if projected_states.size() != 4:
						failures.append("projected gait states missing: %s" % facing)
	if genome.debug_summary() != original_summary:
		failures.append("facing projection mutated genome")


func _validate_modular_renderer(genome: Resource, failures: Array[String]) -> void:
	if SPRITE_SET == null or not SPRITE_SET.is_valid():
		failures.append("modular sprite-set resource is incomplete")
		return
	for facing: String in FacingProjection.FACINGS:
		var parts: Dictionary = SPRITE_SET.get_parts_for_facing(facing)
		for required: String in SPRITE_SET.REQUIRED_PARTS:
			if not parts.has(required) or parts[required] == null or not SPRITE_SET.part_pivots.has(required):
				failures.append("missing modular part or pivot: %s %s" % [facing, required])
	if not SPRITE_SET.should_mirror("NW") or not SPRITE_SET.should_mirror("SW") or SPRITE_SET.should_mirror("NE") or SPRITE_SET.should_mirror("SE"):
		failures.append("modular mirroring policy invalid")
	var original_summary: String = genome.debug_summary()
	var source: Node2D = CreatureVisual.new()
	source.configure(genome, CreatureVisual.MODE_NORMAL)
	source.set_animation(RigScript.GAIT_PLANTED, 1.0, true)
	get_root().add_child(source)
	var modular: Node2D = ModularRenderer.new()
	modular.configure(genome, SPRITE_SET, source, ModularRenderer.MODE_NORMAL)
	get_root().add_child(modular)
	await process_frame
	if modular.get_sprite_count() != 20:
		failures.append("unexpected modular sprite count: %d" % modular.get_sprite_count())
	for facing: String in FacingProjection.FACINGS:
		source.set_facing(facing)
		modular.refresh_from_pose()
		var pose: Dictionary = source.get_projected_pose()
		var transforms: Dictionary = modular.get_transform_snapshot()
		for key: String in transforms:
			var transform_data: Dictionary = transforms[key]
			if not Vector2(transform_data.position).is_finite() or not Vector2(transform_data.scale).is_finite() or not is_finite(float(transform_data.rotation)):
				failures.append("non-finite modular transform: %s %s" % [facing, key])
		for role: String in RigScript.FOOT_KEYS:
			var solution: Dictionary = pose["%s_ik" % role]
			if Vector2(transforms["%s_upper" % role].position).distance_to(solution.root) > 0.001:
				failures.append("upper sprite pivot misaligned: %s %s" % [facing, role])
			if Vector2(transforms["%s_lower" % role].position).distance_to(solution.joint) > 0.001:
				failures.append("lower sprite pivot misaligned: %s %s" % [facing, role])
			if Vector2(transforms["%s_foot" % role].position).distance_to(pose["%s_foot" % role]) > 0.001:
				failures.append("foot sprite endpoint misaligned: %s %s" % [facing, role])
		if Vector2(transforms.tail_base.position).distance_to(pose.tail_root) > 0.001 or Vector2(transforms.tail_mid.position).distance_to(pose.tail_mid) > 0.001:
			failures.append("modular tail segments disconnected: %s" % facing)
		var textures: Dictionary = modular.get_texture_snapshot()
		if String(_genome_ear_texture_key(genome)) not in textures.near_ear:
			failures.append("ear profile selected wrong authored part: %s" % facing)
	if genome.debug_summary() != original_summary:
		failures.append("modular renderer mutated genome")
	var rebuild_start: int = Time.get_ticks_usec()
	var benchmark_renderers: Array[Node2D] = []
	for _index in range(12):
		var instance: Node2D = ModularRenderer.new()
		instance.configure(genome, SPRITE_SET, source, ModularRenderer.MODE_NORMAL)
		benchmark_renderers.append(instance)
	var rebuild_usec: int = Time.get_ticks_usec() - rebuild_start
	var update_start: int = Time.get_ticks_usec()
	for _frame in range(10):
		for instance: Node2D in benchmark_renderers: instance.refresh_from_pose()
	var update_usec: int = Time.get_ticks_usec() - update_start
	print("CREATURE_MODULAR_BENCHMARK sprites_per=20 nodes_per=21 polygon_canvas_items_per=1 rebuild12_usec=%d update12x10_usec=%d" % [rebuild_usec, update_usec])
	for instance: Node2D in benchmark_renderers:
		instance.free()
	modular.free()
	source.free()


func _genome_ear_texture_key(genome: Resource) -> String:
	return "ear_%s" % String(genome.ear_profile)


func _validate_body_outlines(specimens: Array[Dictionary], failures: Array[String]) -> void:
	var genomes: Array[Resource] = []
	for seed in range(32): genomes.append(GenomeGenerator.generate(DEFINITION, seed))
	for specimen: Dictionary in specimens: genomes.append(specimen.genome)
	for genome: Resource in genomes:
		for facing: String in FacingProjection.FACINGS:
			var visual: Node2D = CreatureVisual.new()
			visual.configure(genome, CreatureVisual.MODE_NORMAL)
			visual.set_facing(facing)
			var points: PackedVector2Array = visual.get_body_outline_points()
			var repeated: PackedVector2Array = visual.get_body_outline_points()
			if points != repeated:
				failures.append("body outline reconstruction is not deterministic: %d %s" % [genome.seed, facing])
				visual.free()
				return
			if points.size() != 14 or not _points_are_finite(points):
				failures.append("body outline missing or non-finite: %d %s" % [genome.seed, facing])
				visual.free()
				return
			if _signed_twice_area(points) <= 0.0:
				failures.append("body outline winding inconsistent: %d %s" % [genome.seed, facing])
				visual.free()
				return
			if _polygon_self_intersects(points):
				failures.append("body outline self-intersects: %d %s" % [genome.seed, facing])
				visual.free()
				return
			var bounds := _point_bounds(points)
			if bounds.size.x < 8.0 or bounds.size.y < 6.0:
				failures.append("body outline collapsed semantic regions: %d %s" % [genome.seed, facing])
				visual.free()
				return
			var pose: Dictionary = visual.get_projected_pose()
			if _distance_to_polygon(pose.head_anchor, points) > float(genome.head_size) * 0.8:
				failures.append("body neck disconnected from head: %d %s" % [genome.seed, facing])
			if _distance_to_polygon(pose.tail_root, points) > float(genome.body_height) * 0.65:
				failures.append("body rump disconnected from tail: %d %s" % [genome.seed, facing])
			for hip_key: String in ["near_front_hip", "far_front_hip", "near_rear_hip", "far_rear_hip"]:
				if not Geometry2D.is_point_in_polygon(pose[hip_key], points) and _distance_to_polygon(pose[hip_key], points) > 4.5:
					failures.append("leg hip detached from body outline: %d %s %s" % [genome.seed, facing, hip_key])
			visual.free()
	print("CREATURE_BODY_OUTLINE_AUDIT genomes=%d facings=%d points=14" % [genomes.size(), FacingProjection.FACINGS.size()])


func _points_are_finite(points: PackedVector2Array) -> bool:
	for point: Vector2 in points:
		if not point.is_finite(): return false
	return true


func _signed_twice_area(points: PackedVector2Array) -> float:
	var result: float = 0.0
	for index in range(points.size()):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % points.size()]
		result += current.x * following.y - following.x * current.y
	return result


func _polygon_self_intersects(points: PackedVector2Array) -> bool:
	for first in range(points.size()):
		var first_next: int = (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_next: int = (second + 1) % points.size()
			if first == second or first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


func _point_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _distance_to_polygon(point: Vector2, points: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, points): return 0.0
	var minimum := INF
	for index in range(points.size()):
		minimum = minf(minimum, Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()]).distance_to(point))
	return minimum


func _first_gallery_root_phase(gallery: Control) -> float:
	for cell in gallery.get_node("Gallery").get_children():
		for child in cell.get_children():
			if child.has_method("get_projected_pose"):
				return float(child.get_projected_pose().root_world_x)
	return -1.0
