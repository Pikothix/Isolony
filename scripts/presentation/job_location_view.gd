extends Control
class_name JobLocationView

signal zoom_changed(percent: int)
signal construction_feedback(message: String)
signal building_inspection_requested(building_id: String)

const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const TERRAIN_TILE_SET = preload("res://TerrainIso.tres")
const ProcSpriteCache = preload("res://scripts/procgen/proc_sprite_cache.gd")
const PropVisualConfig = preload("res://scripts/world/props/prop_visual_config.gd")
const ColonistVisualScript = preload("res://scripts/presentation/location_colonist_visual.gd")
const ConstructionVisualScript = preload("res://scripts/buildings/construction_site_visual.gd")
const BuildingDefinition = preload("res://scripts/buildings/building_definition.gd")
const ConstructionPieceDefinitions = preload("res://scripts/simulation/construction_piece_definitions.gd")
const CONSTRUCTION_TILE_SET = preload("res://assets/location_construction_tiles.tres")
const ConstructionVisualConfig = preload("res://scripts/presentation/location_construction_visual_config.gd")
const ZOOM_STEPS := [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

@export var profile_debug := false
@export var construction_input_debug := false

var colony_state: Node
var location_id := ""
var _construction_tool_provider: Callable
var _zoom_index := 2
var _pan := Vector2.ZERO
var _panning := false
var _rendering_suspended := false
var _map_root: Node2D
var _terrain_layer: TileMapLayer
var _depth_root: Node2D
var _construction_floor_layer: TileMapLayer
var _construction_wall_layer: TileMapLayer
var _construction_opening_layer: TileMapLayer
var _construction_floor_ghost_layer: TileMapLayer
var _construction_elevated_ghost_layer: TileMapLayer
var _construction_floor_hover_layer: TileMapLayer
var _construction_elevated_hover_layer: TileMapLayer
var _resource_root: Node2D
var _pile_root: Node2D
var _colonist_root: Node2D
var _building_root: Node2D
var _resource_nodes: Dictionary = {}
var _pile_nodes: Dictionary = {}
var _colonist_nodes: Dictionary = {}
var _building_nodes: Dictionary = {}
var _construction_depth_nodes: Dictionary = {}
var _placement_preview: Node2D
var _placement_mode := false
var _construction_dragging := false
var _construction_drag_cells: Array[Vector2i] = []
var _construction_drag_start_cell := Vector2i.ZERO
var _hovered_construction_cell := Vector2i(-1, -1)
var _resolved_placement_target: Dictionary = {}
var _selected_orientation_by_piece: Dictionary = {}
var _hovered_construction_site_id := ""
var _debug_preview_logged := false
var _debug_click_logged := false
var _terrain_build_count := 0
var _resource_full_build_count := 0
var _full_snapshot_count := 0
var _profile_started_usec := 0

## Event-driven, reconstructible bounded-location projection. Static atlas
## terrain and resource sprites build once per opening; focused events update deltas.
func configure(state: Node, target_location_id: String, construction_tool_provider := Callable()) -> void:
	colony_state = state
	location_id = target_location_id
	_construction_tool_provider = construction_tool_provider
	custom_minimum_size = Vector2(470, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(_clear_current_construction_preview)
	_build_roots()
	var location: Dictionary = _full_location_snapshot()
	_build_terrain(location)
	_build_resources(location)
	_build_piles(location)
	_build_buildings(location)
	_rebuild_location_construction()
	_rebuild_colonist_visuals()
	state.location_changed.connect(_on_location_changed)
	state.colonist_motion_changed.connect(_on_colonist_motion_changed)
	state.haul_state_changed.connect(_on_haul_state_changed)
	state.building_changed.connect(_on_building_changed)
	state.location_construction_changed.connect(_on_location_construction_changed)
	_apply_camera()


func set_rendering_suspended(suspended: bool) -> void:
	if _rendering_suspended == suspended: return
	_rendering_suspended = suspended
	visible = not suspended
	if not suspended: _refresh_from_authority()
	if profile_debug: _profile_report("suspend" if suspended else "resume")


func _refresh_from_authority() -> void:
	var location := _full_location_snapshot()
	for node: Node in _resource_nodes.values(): if is_instance_valid(node): node.queue_free()
	for node: Node in _pile_nodes.values(): if is_instance_valid(node): node.queue_free()
	for node: Node in _building_nodes.values(): if is_instance_valid(node): node.queue_free()
	for node: Node in _colonist_nodes.values(): if is_instance_valid(node): node.queue_free()
	_resource_nodes.clear(); _pile_nodes.clear(); _building_nodes.clear(); _colonist_nodes.clear()
	_build_resources(location)
	_build_piles(location)
	_build_buildings(location)
	_rebuild_location_construction()
	_rebuild_colonist_visuals()


func zoom_in() -> void: _set_zoom_index(_zoom_index + 1, size * 0.5)
func zoom_out() -> void: _set_zoom_index(_zoom_index - 1, size * 0.5)
func get_zoom_percent() -> int: return roundi(float(ZOOM_STEPS[_zoom_index]) * 100.0)
func get_terrain_build_count() -> int: return _terrain_build_count
func get_resource_full_build_count() -> int: return _resource_full_build_count
func get_full_snapshot_count() -> int: return _full_snapshot_count
func is_rendering_suspended() -> bool: return _rendering_suspended
func begin_supply_cache_placement() -> void:
	_clear_current_construction_preview()
	_placement_mode = true
func cancel_placement() -> void:
	_placement_mode = false
	_resolved_placement_target.clear()
	if _placement_preview != null: _placement_preview.queue_free(); _placement_preview = null
func cancel_construction_interaction() -> void:
	_construction_dragging = false
	_construction_drag_cells.clear()
	_clear_current_construction_preview()


func _build_roots() -> void:
	_map_root = Node2D.new(); _map_root.name = "MapRoot"; add_child(_map_root)
	_terrain_layer = TileMapLayer.new(); _terrain_layer.name = "BoundedTerrain"; _terrain_layer.tile_set = TERRAIN_TILE_SET; _terrain_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; _terrain_layer.z_index = 0; _map_root.add_child(_terrain_layer)
	_construction_floor_layer = _new_floor_construction_layer("CompletedFloors", 0)
	# Elevated aggregate layers remain as hidden semantic indexes for focused validation.
	# Rendered elevated cells are individual nodes under DepthSortedWorld.
	_construction_wall_layer = _new_construction_layer("CompletedWallsIndex", 0, true); _construction_wall_layer.visible = false
	_construction_opening_layer = _new_construction_layer("CompletedOpeningsIndex", 0, true); _construction_opening_layer.visible = false
	_construction_floor_ghost_layer = _new_floor_construction_layer("FloorConstructionGhosts", 0)
	_construction_floor_ghost_layer.visible = false
	_construction_elevated_ghost_layer = _new_construction_layer("ElevatedConstructionGhostsIndex", 0, true); _construction_elevated_ghost_layer.visible = false
	_construction_floor_hover_layer = _new_floor_construction_layer("FloorConstructionHover", 1)
	_construction_elevated_hover_layer = _new_construction_layer("ElevatedConstructionHover", 1, true)
	_depth_root = Node2D.new(); _depth_root.name = "DepthSortedWorld"; _depth_root.y_sort_enabled = true; _map_root.add_child(_depth_root)
	# All depth-interacting visuals are direct children of one Y-sorted owner.
	_resource_root = _depth_root; _pile_root = _depth_root; _building_root = _depth_root; _colonist_root = _depth_root

func _new_construction_layer(layer_name: String, layer_z: int, elevated := false) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name; layer.tile_set = CONSTRUCTION_TILE_SET; layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; layer.z_index = layer_z
	if elevated: layer.position = ConstructionVisualConfig.WALL_VISUAL_OFFSET
	_map_root.add_child(layer)
	return layer

func _new_floor_construction_layer(layer_name: String, layer_z: int) -> TileMapLayer:
	var layer := _new_construction_layer(layer_name, layer_z)
	# Floor atlas cells carry an 8 px texture origin; cancel it once at the
	# aggregate layer so preview, ghost, and completion share the terrain lattice.
	layer.position = ConstructionVisualConfig.FLOOR_LAYER_OFFSET
	return layer


func _full_location_snapshot() -> Dictionary:
	_full_snapshot_count += 1
	return colony_state.get_location_snapshot(location_id)


func _build_terrain(location: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	_terrain_build_count += 1
	for tile: Dictionary in location.terrain:
		var atlas := TerrainConfigRef.get_visual_atlas_coords(String(tile.terrain), TerrainConfigRef.VISUAL_VARIANT_FLAT, Vector2i(tile.atlas_coords))
		_terrain_layer.set_cell(Vector2i(tile.cell), TerrainConfigRef.TILE_SOURCE_ID, atlas)
	if profile_debug:
		print("LOCATION_VIEW_PROFILE terrain_build location=", location_id, " count=", _terrain_build_count, " usec=", Time.get_ticks_usec() - start)


func _build_resources(location: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	_resource_full_build_count += 1
	for resource: Dictionary in location.resources:
		if not bool(resource.depleted): _add_resource_visual(resource, location)
	if profile_debug:
		print("LOCATION_VIEW_PROFILE resource_full_build location=", location_id, " count=", _resource_full_build_count, " nodes=", _resource_nodes.size(), " usec=", Time.get_ticks_usec() - start, " cache=", ProcSpriteCache.get_cache_size())


func _add_resource_visual(resource: Dictionary, location: Dictionary) -> void:
	var resource_id := String(resource.resource_id)
	if _resource_nodes.has(resource_id): return
	var anchor := Node2D.new(); anchor.name = resource_id
	var sprite := Sprite2D.new(); sprite.name = "Sprite"
	var chunk_coord := Vector2i(int(resource.cell.x) / 16, int(resource.cell.y) / 16)
	var config := PropVisualConfig.build_resource_visual_config(resource, chunk_coord, 16, int(location.seed), true, true, 18, 12, 30, 14, 18, 22)
	sprite.texture = ProcSpriteCache.get_texture(String(config.procedural_sprite_kind), int(config.procedural_seed), int(config.procedural_sprite_size), int(config.procedural_variant_cap), String(config.procedural_archetype), String(config.procedural_terrain_tag), String(config.procedural_size_tier))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anchor.position = _terrain_layer.map_to_local(Vector2i(resource.cell)); sprite.position = Vector2(0, -10)
	anchor.add_child(sprite); _resource_root.add_child(anchor)
	_resource_nodes[resource_id] = anchor


func _build_piles(location: Dictionary) -> void:
	for pile: Dictionary in location.piles: _update_pile_visual(pile)

func _build_buildings(location: Dictionary) -> void:
	for building: Dictionary in location.get("building_records", []): _update_building_visual(building)

func _rebuild_location_construction() -> void:
	for node: Node in _construction_depth_nodes.values():
		if is_instance_valid(node): node.queue_free()
	_construction_depth_nodes.clear()
	for layer: TileMapLayer in [_construction_floor_layer, _construction_wall_layer, _construction_opening_layer, _construction_floor_ghost_layer, _construction_elevated_ghost_layer]: layer.clear()
	var completed: Dictionary = colony_state.get_location_completed_structures(location_id)
	for cell: Vector2i in completed.floor_cells: _set_construction_cell(_construction_floor_layer, cell, "floor")
	var elevated_parts: Dictionary = {}
	for cell: Vector2i in completed.structure_cells:
		var structure: Dictionary = completed.structure_cells[cell]
		var fixture_kind := String(structure.get("fixture_kind", ""))
		var fixture_orientation := String(structure.get("fixture_orientation", ""))
		var visual := ConstructionVisualConfig.resolve_structure_visual(String(structure.get("kind", "")), fixture_kind, fixture_orientation)
		if String(visual.mode) == "unsupported": continue
		_set_construction_cell(_construction_wall_layer, cell, "wall")
		if String(visual.mode) == "layered": _set_construction_cell(_construction_opening_layer, cell, fixture_kind, fixture_orientation)
		for part: Dictionary in visual.parts:
			_append_structure_part(elevated_parts, structure, {"kind": String(part.kind), "axis": String(part.axis), "alpha": 1.0})
	for site: Dictionary in colony_state.get_location_construction_sites(location_id):
		var target := _construction_floor_ghost_layer if String(site.piece_kind) == "floor" else _construction_elevated_ghost_layer
		_set_construction_cell(target, Vector2i(site.cell), String(site.piece_kind), String(site.orientation_axis))
		var status: Dictionary = colony_state.get_construction_site_status(location_id, String(site.site_id))
		var tint := ConstructionVisualConfig.ghost_tint(String(status.status), String(status.availability_reason), float(status.progress), float(status.build_required))
		if String(site.piece_kind) == "floor":
			var floor_anchor := Node2D.new(); floor_anchor.name = "FloorConstruction_%s" % String(site.site_id); floor_anchor.position = _terrain_layer.map_to_local(Vector2i(site.cell)) + ConstructionVisualConfig.FLOOR_LAYER_OFFSET
			var floor_part := TileMapLayer.new(); floor_part.tile_set = CONSTRUCTION_TILE_SET; floor_part.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; floor_part.position = -floor_part.map_to_local(Vector2i.ZERO); floor_part.modulate = tint
			floor_anchor.add_child(floor_part); _map_root.add_child(floor_anchor); _map_root.move_child(floor_anchor, _depth_root.get_index()); _construction_depth_nodes["floor_%s" % String(site.site_id)] = floor_anchor
			_set_construction_cell(floor_part, Vector2i.ZERO, "floor")
		else:
			_append_structure_part(elevated_parts, site, {"kind": String(site.piece_kind), "axis": String(site.orientation_axis), "tint": tint})
	for structure_id: String in elevated_parts:
		var entry: Dictionary = elevated_parts[structure_id]
		var anchor := Node2D.new(); anchor.name = "Construction_%s" % structure_id; anchor.position = _terrain_layer.map_to_local(Vector2i(entry.cell))
		_depth_root.add_child(anchor); _construction_depth_nodes[structure_id] = anchor
		var part_index := 0
		for part: Dictionary in entry.parts:
			var layer := TileMapLayer.new(); layer.name = "Part%d" % part_index; layer.tile_set = CONSTRUCTION_TILE_SET; layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# A per-cell TileMap still maps local cell zero to the TileSet's half-cell
			# origin. Cancel that map origin so the child owns only pixel calibration.
			layer.position = ConstructionVisualConfig.WALL_VISUAL_OFFSET - layer.map_to_local(Vector2i.ZERO)
			layer.modulate = part.get("tint", Color(1.0, 1.0, 1.0, float(part.get("alpha", 1.0)))); anchor.add_child(layer)
			_set_construction_cell(layer, Vector2i.ZERO, String(part.kind), String(part.axis)); part_index += 1

func _append_structure_part(index: Dictionary, structure: Dictionary, part: Dictionary) -> void:
	var cell := Vector2i(structure.cell)
	var structure_id := "%d_%d" % [cell.x, cell.y]
	if not index.has(structure_id): index[structure_id] = {"cell": cell, "parts": []}
	index[structure_id].parts.append(part)

func _set_construction_cell(layer: TileMapLayer, cell: Vector2i, piece_kind: String, axis := "") -> void:
	var atlas := ConstructionVisualConfig.atlas_for(piece_kind, axis)
	if atlas != Vector2i(-1, -1): layer.set_cell(cell, ConstructionVisualConfig.TILE_SOURCE_ID, atlas)

func _update_building_visual(building: Dictionary) -> void:
	var id := String(building.building_instance_id); var visual: Node2D
	if bool(building.get("derived_enclosure", false)):
		_remove_visual(_building_nodes, id)
		return
	if _building_nodes.has(id): visual = _building_nodes[id]
	else: visual = ConstructionVisualScript.new(); visual.name = id; _building_root.add_child(visual); _building_nodes[id] = visual
	var definition := BuildingDefinition.get_definition(String(building.building_id)); var metadata := BuildingDefinition.get_visual_metadata(String(building.building_id))
	visual.position = _terrain_layer.map_to_local(Vector2i(building.origin_cell))
	visual.configure_building_site(String(building.building_id), String(building.state) == "COMPLETED", Vector2i(definition.footprint), 0.0, 0.0, 0.0, 0, false, String(metadata.construction_visual_id), String(metadata.completed_visual_id), "", "", metadata.placeholder_palette)


func _update_pile_visual(pile: Dictionary) -> void:
	var pile_id := String(pile.pile_id)
	if not bool(pile.enabled) or int(pile.amount) <= 0:
		_remove_visual(_pile_nodes, pile_id)
		return
	var root_node: Node2D
	if _pile_nodes.has(pile_id): root_node = _pile_nodes[pile_id]
	else:
		root_node = Node2D.new(); root_node.name = pile_id; _pile_root.add_child(root_node); _pile_nodes[pile_id] = root_node
		var body := Polygon2D.new(); body.name = "Body"; root_node.add_child(body)
		var label := Label.new(); label.name = "Amount"; label.mouse_filter = Control.MOUSE_FILTER_IGNORE; label.position = Vector2(-12, -25); label.add_theme_color_override("font_color", Color.WHITE); label.add_theme_color_override("font_outline_color", Color.BLACK); label.add_theme_constant_override("outline_size", 2); label.add_theme_font_size_override("font_size", 10); root_node.add_child(label)
	root_node.position = _terrain_layer.map_to_local(Vector2i(pile.cell))
	var body: Polygon2D = root_node.get_node("Body")
	match String(pile.resource_type):
		"wood": body.color = Color("#8b5a2b")
		"food": body.color = Color("#9f3154")
		_: body.color = Color("#8f939b")
	if bool(pile.get("stored", false)): body.color = body.color.lightened(0.2)
	body.polygon = PackedVector2Array([Vector2(-9, 1), Vector2(-6, -7), Vector2(0, -11), Vector2(9, -5), Vector2(8, 3), Vector2(0, 6)])
	var label: Label = root_node.get_node("Amount"); label.text = "%d%s" % [int(pile.amount), " R" if int(pile.reserved_amount) > 0 else ""]


func _rebuild_colonist_visuals() -> void:
	for colonist_id: String in colony_state.get_colonist_ids(): _update_colonist_visual(colonist_id)


func _update_colonist_visual(colonist_id: String) -> void:
	var colonist: Dictionary = colony_state.get_colonist_snapshot(colonist_id)
	if String(colonist.location_id) != location_id:
		_remove_visual(_colonist_nodes, colonist_id)
		return
	var visual: Node2D
	if _colonist_nodes.has(colonist_id): visual = _colonist_nodes[colonist_id]
	else:
		visual = ColonistVisualScript.new(); visual.name = colonist_id; _colonist_root.add_child(visual); _colonist_nodes[colonist_id] = visual
	visual.position = _terrain_layer.map_to_local(Vector2i(Vector2(colonist.visual_cell).round()))
	visual.configure_from_snapshot(colonist)


func _on_location_changed(changed_location_id: String, change_type: String, subject_id: String) -> void:
	if _rendering_suspended: return
	if changed_location_id != location_id: return
	match change_type:
		"resource_depleted": _remove_visual(_resource_nodes, subject_id)
		"pile": _update_pile_visual(colony_state.get_pile_snapshot(location_id, subject_id))
		"assignment": _rebuild_colonist_visuals()


func _on_colonist_motion_changed(colonist_id: String, changed_location_id: String) -> void:
	if _rendering_suspended: return
	if changed_location_id == location_id or _colonist_nodes.has(colonist_id): _update_colonist_visual(colonist_id)


func _on_haul_state_changed(colonist_id: String) -> void:
	if _rendering_suspended: return
	if _colonist_nodes.has(colonist_id): _update_colonist_visual(colonist_id)
func _on_building_changed(changed_location_id: String, building_id: String) -> void:
	if _rendering_suspended: return
	if changed_location_id == location_id: _update_building_visual(colony_state.get_building_snapshot(building_id))
func _on_location_construction_changed(changed_location_id: String, _change_type: String, _site_id: String) -> void:
	if _rendering_suspended: return
	if changed_location_id == location_id:
		_rebuild_location_construction(); _update_hovered_site()
		for pile: Dictionary in colony_state.get_location_snapshot(location_id).piles: _update_pile_visual(pile)
		if not _resolved_placement_target.is_empty():
			_refresh_pointer_target(Vector2(_resolved_placement_target.view_position), _active_construction_tool())


func _remove_visual(index: Dictionary, key: String) -> void:
	if not index.has(key): return
	var node: Node = index[key]
	index.erase(key)
	if is_instance_valid(node): node.queue_free()


func _on_gui_input(event: InputEvent) -> void:
	var construction_tool := _active_construction_tool()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and ConstructionPieceDefinitions.is_rotatable(construction_tool):
		_rotate_construction_orientation(construction_tool)
		construction_feedback.emit("Rotated %s to %s" % [construction_tool, _orientation_for_tool(construction_tool).replace("axis_", "axis ")])
		accept_event()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE and not _hovered_construction_site_id.is_empty():
		var cancelled: Dictionary = colony_state.request_cancel_construction(location_id, _hovered_construction_site_id); construction_feedback.emit("Cancelled designation" if bool(cancelled.ok) else String(cancelled.reason).replace("_", " ")); accept_event(); return
	if event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative; _apply_camera(); _refresh_pointer_target(event.position, construction_tool); accept_event(); return
		_hovered_construction_cell = _screen_to_cell(event.position); _update_hovered_site()
		_refresh_pointer_target(event.position, construction_tool)
		if construction_tool in ["wall", "door", "window"] or construction_tool == "floor" or _placement_mode: accept_event(); return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var cancellation_site_id := _site_at_hover(bool(event.shift_pressed))
		if not cancellation_site_id.is_empty():
			var cancelled: Dictionary = colony_state.request_cancel_construction(location_id, cancellation_site_id)
			if bool(cancelled.ok):
				var count: int = cancelled.get("cancelled_site_ids", []).size()
				construction_feedback.emit("Cancelled designation" if count <= 1 else "Cancelled wall and %d dependent designation(s)" % (count - 1))
			else: construction_feedback.emit(String(cancelled.reason).replace("_", " "))
			accept_event(); return
	if construction_tool in ["wall", "door", "window"] and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if String(_resolved_placement_target.get("tool_kind", "")) != construction_tool or _resolved_placement_target.get("targets", []).is_empty(): construction_feedback.emit("No structure preview")
		else:
			var shown_target := Vector2i(_resolved_placement_target.cell)
			var submitted_targets: Array = _resolved_placement_target.get("submission_targets", [shown_target]).duplicate(true)
			var result: Dictionary = colony_state.request_designate_construction(location_id, construction_tool, submitted_targets)
			_debug_click_submission(event, shown_target, result)
			construction_feedback.emit(("Designated " + construction_tool) if bool(result.ok) else String(result.reason).replace("_", " "))
		accept_event(); return
	if construction_tool == "floor" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if event.pressed:
			if String(_resolved_placement_target.get("tool_kind", "")) != construction_tool or _resolved_placement_target.get("targets", []).is_empty(): construction_feedback.emit("No floor preview"); accept_event(); return
			_construction_dragging = true; _construction_drag_start_cell = Vector2i(_resolved_placement_target.cell); _construction_drag_cells = [Vector2i(_resolved_placement_target.cell)]
		else:
			var submitted_cells: Array = _resolved_placement_target.get("targets", []).duplicate()
			_construction_dragging = false
			if submitted_cells.is_empty(): construction_feedback.emit("No floor preview")
			else:
				var result: Dictionary = colony_state.request_designate_construction(location_id, construction_tool, submitted_cells)
				construction_feedback.emit(("Designated %d floor cell(s)" % submitted_cells.size()) if bool(result.ok) else String(result.reason).replace("_", " "))
			_construction_drag_cells.clear()
		accept_event(); return
	if _placement_mode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var location: Dictionary = colony_state.get_location_snapshot(location_id)
		if not location.colonist_presence_ids.is_empty():
			if String(_resolved_placement_target.get("tool_kind", "")) != "building" or _resolved_placement_target.get("targets", []).is_empty(): construction_feedback.emit("No building preview"); accept_event(); return
			var cell := Vector2i(_resolved_placement_target.cell)
			var result: Dictionary = colony_state.request_place_building(String(location.colonist_presence_ids[0]), location_id, "supply_cache", cell)
			if bool(result.ok): cancel_placement()
		accept_event(); return
	if construction_tool.is_empty() and not _placement_mode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var building_id := _building_at_cell(_screen_to_cell(event.position))
		if not building_id.is_empty():
			building_inspection_requested.emit(building_id)
			accept_event(); return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: _set_zoom_index(_zoom_index + 1, event.position); accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: _set_zoom_index(_zoom_index - 1, event.position); accept_event()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]: _panning = event.pressed; accept_event()

func _active_construction_tool() -> String:
	if not _construction_tool_provider.is_valid(): return ""
	return String(_construction_tool_provider.call())

## Resolves pointer input once into a transient presentation record. Preview
## rendering and click submission both consume this record; simulation remains
## the owner of authoritative validation and mutation.
func _refresh_pointer_target(view_position: Vector2, construction_tool: String) -> void:
	_clear_construction_hover()
	if construction_tool in ["wall", "door", "window"]:
		var cell := _screen_to_cell(view_position)
		var target_request: Variant = {"cell": cell, "orientation_axis": _orientation_for_tool(construction_tool)} if ConstructionPieceDefinitions.is_rotatable(construction_tool) else cell
		var validation: Dictionary = colony_state.validate_construction_designation(location_id, construction_tool, [target_request])
		_resolved_placement_target = {
			"tool_kind": construction_tool,
			"world_space_id": location_id,
			"target_cell": cell,
			"cell": cell,
			"targets": [cell],
			"submission_targets": [target_request],
			"orientation_axis": _orientation_for_tool(construction_tool),
			"valid": bool(validation.ok),
			"reason": String(validation.reason),
			"validation": validation,
			"view_position": view_position,
		}
		_render_cell_construction_target(_resolved_placement_target)
		_debug_preview_frame(view_position, validation)
		_update_hovered_site()
		return
	if construction_tool == "floor":
		var cell := _screen_to_cell(view_position)
		var cells: Array[Vector2i] = []
		if _construction_dragging: cells = _cells_on_line(_construction_drag_start_cell, cell)
		else: cells.append(cell)
		var validation: Dictionary = colony_state.validate_construction_designation(location_id, construction_tool, cells)
		_resolved_placement_target = {
			"tool_kind": construction_tool,
			"world_space_id": location_id,
			"cell": cell,
			"targets": cells,
			"valid": bool(validation.ok),
			"reason": String(validation.reason),
			"validation": validation,
			"view_position": view_position,
		}
		_construction_drag_cells = cells.duplicate()
		_render_cell_construction_target(_resolved_placement_target)
		return
	if _placement_mode:
		var cell := _screen_to_cell(view_position)
		var validation: Dictionary = colony_state.validate_building_placement(location_id, "supply_cache", cell)
		_resolved_placement_target = {
			"tool_kind": "building",
			"building_id": "supply_cache",
			"world_space_id": location_id,
			"cell": cell,
			"targets": [cell],
			"valid": bool(validation.ok),
			"reason": String(validation.reason),
			"validation": validation,
			"view_position": view_position,
		}
		_update_placement_preview(_resolved_placement_target)
		return
	_resolved_placement_target.clear()

func _render_cell_construction_target(resolved: Dictionary) -> void:
	var target := _construction_floor_hover_layer if String(resolved.tool_kind) == "floor" else _construction_elevated_hover_layer
	var axis := String(resolved.get("orientation_axis", ""))
	for cell: Vector2i in resolved.targets: _set_construction_cell(target, cell, String(resolved.tool_kind), axis)
	var preview_prerequisites: Array = resolved.validation.get("records", [{}])[0].get("prerequisite_site_ids", []) if bool(resolved.valid) else []
	if not preview_prerequisites.is_empty(): target.modulate = ConstructionVisualConfig.GHOST_PREREQUISITE
	else: target.modulate = Color(0.45, 1.0, 0.55, 0.72) if bool(resolved.valid) else Color(1.0, 0.3, 0.3, 0.72)

func _orientation_for_tool(piece_kind: String) -> String:
	var orientations := ConstructionPieceDefinitions.get_orientations(piece_kind)
	if orientations.is_empty(): return ""
	var selected := String(_selected_orientation_by_piece.get(piece_kind, orientations[0]))
	if selected not in orientations: selected = String(orientations[0])
	_selected_orientation_by_piece[piece_kind] = selected
	return selected

func _rotate_construction_orientation(piece_kind: String) -> void:
	var orientations := ConstructionPieceDefinitions.get_orientations(piece_kind)
	if orientations.size() < 2: return
	var current := _orientation_for_tool(piece_kind)
	_selected_orientation_by_piece[piece_kind] = String(orientations[(orientations.find(current) + 1) % orientations.size()])
	if not _resolved_placement_target.is_empty() and String(_resolved_placement_target.get("tool_kind", "")) == piece_kind:
		_refresh_pointer_target(Vector2(_resolved_placement_target.view_position), piece_kind)

func _building_at_cell(cell: Vector2i) -> String:
	for building: Dictionary in colony_state.get_building_snapshots(location_id):
		if cell in building.get("occupied_cells", []): return String(building.building_instance_id)
	return ""

func _screen_to_cell(view_position: Vector2) -> Vector2i:
	# Construction picking is owned by the location view and always projects the
	# pointer onto terrain. Raised sprites, walls, openings, and ghosts are not
	# consulted as picking surfaces.
	return _terrain_layer.local_to_map(_view_to_map_local(view_position))

func _view_to_map_local(view_position: Vector2) -> Vector2:
	var viewport_position := get_global_transform_with_canvas() * view_position
	return _terrain_layer.get_global_transform_with_canvas().affine_inverse() * viewport_position

func debug_view_position_to_cell(view_position: Vector2) -> Vector2i:
	return _screen_to_cell(view_position)

func debug_cell_to_view_position(cell: Vector2i) -> Vector2:
	var canvas_position := _terrain_layer.get_global_transform_with_canvas() * _terrain_layer.map_to_local(cell)
	return get_global_transform_with_canvas().affine_inverse() * canvas_position

func _update_construction_hover(piece_kind: String, cells: Array[Vector2i]) -> void:
	_clear_construction_hover()
	var validation: Dictionary = colony_state.validate_construction_designation(location_id, piece_kind, cells)
	var target := _construction_floor_hover_layer if piece_kind == "floor" else _construction_elevated_hover_layer
	var axis := String(validation.get("records", [{}])[0].get("orientation_axis", "")) if bool(validation.ok) else ""
	if axis.is_empty() and piece_kind in ["door", "window"]: axis = "axis_x"
	for cell: Vector2i in cells: _set_construction_cell(target, cell, piece_kind, axis)
	var preview_prerequisites: Array = validation.get("records", [{}])[0].get("prerequisite_site_ids", []) if bool(validation.ok) else []
	if not preview_prerequisites.is_empty():
		target.modulate = ConstructionVisualConfig.GHOST_PREREQUISITE
	else: target.modulate = Color(0.45, 1.0, 0.55, 0.72) if bool(validation.ok) else Color(1.0, 0.3, 0.3, 0.72)

func _clear_construction_hover() -> void:
	if _construction_floor_hover_layer != null: _construction_floor_hover_layer.clear()
	if _construction_elevated_hover_layer != null: _construction_elevated_hover_layer.clear()

func _clear_current_construction_preview() -> void:
	_resolved_placement_target.clear()
	_debug_preview_logged = false
	_debug_click_logged = false
	_clear_construction_hover()
	if _placement_preview != null:
		_placement_preview.queue_free()
		_placement_preview = null

func _debug_preview_frame(mouse_location_local: Vector2, validation: Dictionary) -> void:
	if not construction_input_debug or _debug_preview_logged: return
	_debug_preview_logged = true
	var mouse_viewport := get_global_transform_with_canvas() * mouse_location_local
	var mouse_screen := get_viewport().get_screen_transform() * mouse_viewport
	var raw_map_cell := _terrain_layer.local_to_map(_view_to_map_local(mouse_location_local))
	print("CONSTRUCTION_PREVIEW_TRACE ", {
		"mouse_screen": mouse_screen,
		"mouse_viewport": mouse_viewport,
		"mouse_location_local": mouse_location_local,
		"raw_map_cell": raw_map_cell,
		"target_cell": Vector2i(_resolved_placement_target.get("cell", Vector2i.ZERO)),
		"preview_cells": _construction_elevated_hover_layer.get_used_cells(),
		"placement_valid": bool(validation.get("ok", false)),
	})

func _debug_click_submission(event: InputEventMouseButton, submitted: Vector2i, result: Dictionary) -> void:
	if not construction_input_debug or _debug_click_logged: return
	_debug_click_logged = true
	var mouse_viewport := get_global_transform_with_canvas() * event.position
	var mouse_screen := get_viewport().get_screen_transform() * mouse_viewport
	print("CONSTRUCTION_CLICK_TRACE ", {
		"mouse_screen": mouse_screen,
		"mouse_viewport": mouse_viewport,
		"mouse_location_local": event.position,
		"raw_map_cell": _terrain_layer.local_to_map(_view_to_map_local(event.position)),
		"preview_cell": Vector2i(_resolved_placement_target.get("cell", Vector2i.ZERO)),
		"submitted_cell": submitted,
		"placement_result": result.duplicate(true),
	})

func _update_hovered_site() -> void:
	_hovered_construction_site_id = _site_at_hover(false)
	if not _hovered_construction_site_id.is_empty(): construction_feedback.emit(_format_construction_status(colony_state.get_construction_site_status(location_id, _hovered_construction_site_id)))

func _site_at_hover(prefer_wall: bool) -> String:
	var matches: Array[Dictionary] = []
	for site: Dictionary in colony_state.get_location_construction_sites(location_id):
		if Vector2i(site.cell) == _hovered_construction_cell: matches.append(site)
	if matches.is_empty(): return ""
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := 0 if (String(a.piece_kind) == "wall") == prefer_wall else 1
		var b_priority := 0 if (String(b.piece_kind) == "wall") == prefer_wall else 1
		return a_priority < b_priority if a_priority != b_priority else String(a.site_id) < String(b.site_id))
	return String(matches[0].site_id)

func _format_construction_status(status: Dictionary) -> String:
	if status.is_empty(): return ""
	var lines: Array[String] = [String(status.piece_kind).capitalize()]
	lines.append("Cell %s" % Vector2i(status.cell))
	match String(status.availability_reason):
		"missing_resources":
			var parts: Array[String] = []
			for resource_kind: String in status.missing_resources: parts.append("%s %d" % [resource_kind.capitalize(), int(status.missing_resources[resource_kind])])
			parts.sort(); lines.append("Waiting for resources: %s" % ", ".join(parts))
		"unreachable": lines.append("No reachable work cell")
		"invalid_dependency": lines.append("Invalid construction dependency")
		"reserved_by_other": lines.append("Reserved by %s" % String(status.reserved_by_colonist_id))
		_:
			if String(status.status) == "reserved": lines.append("Reserved by %s" % String(status.reserved_by_colonist_id))
			elif String(status.status) == "under_construction": lines.append("Actively constructing")
	lines.append("Progress: %.1f / %.1f" % [float(status.progress), float(status.build_required)])
	return "\n".join(lines)

func _cells_on_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta := to - from
	# RimWorld-style dominant-axis placement: ties choose X, and the minor axis
	# remains fixed at the press cell so the preview exactly matches submission.
	if absi(delta.x) >= absi(delta.y):
		var step := 1 if delta.x >= 0 else -1
		for x in range(from.x, to.x + step, step): result.append(Vector2i(x, from.y))
	else:
		var step := 1 if delta.y >= 0 else -1
		for y in range(from.y, to.y + step, step): result.append(Vector2i(from.x, y))
	return result

func _update_placement_preview(resolved: Dictionary) -> void:
	var cell := Vector2i(resolved.cell)
	if _placement_preview == null: _placement_preview = ConstructionVisualScript.new(); _placement_preview.name = "PlacementPreview"; _map_root.add_child(_placement_preview)
	_placement_preview.position = _terrain_layer.map_to_local(cell); var definition := BuildingDefinition.get_definition("supply_cache"); var metadata := BuildingDefinition.get_visual_metadata("supply_cache")
	_placement_preview.configure_preview(bool(resolved.valid), "supply_cache", Vector2i(definition.footprint), String(metadata.construction_visual_id), metadata.placeholder_palette)


func _set_zoom_index(value: int, anchor: Vector2) -> void:
	var next := clampi(value, 0, ZOOM_STEPS.size() - 1)
	if next == _zoom_index: return
	var old_zoom := float(ZOOM_STEPS[_zoom_index]); var new_zoom := float(ZOOM_STEPS[next]); var centre := size * 0.5
	_pan = anchor - centre - (anchor - centre - _pan) * (new_zoom / old_zoom)
	_zoom_index = next; _apply_camera(); zoom_changed.emit(get_zoom_percent())


func _apply_camera() -> void:
	if _map_root == null: return
	var zoom := float(ZOOM_STEPS[_zoom_index]); _map_root.scale = Vector2.ONE * zoom; _map_root.position = size * 0.5 + _pan + Vector2(0, -120) * zoom


func _profile_report(reason: String) -> void:
	if _profile_started_usec == 0: _profile_started_usec = Time.get_ticks_usec()
	print("LOCATION_VIEW_PROFILE ", reason, " location=", location_id, " terrain_builds=", _terrain_build_count, " resource_full_builds=", _resource_full_build_count, " full_snapshots=", _full_snapshot_count, " elapsed_usec=", Time.get_ticks_usec() - _profile_started_usec)
