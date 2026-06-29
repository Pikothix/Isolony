extends Node2D

## Purpose: Coordinate the playable scene, transient control tools, and requests into simulation authorities.
## Responsibility: Own Build/Harvest input and previews, including harvest drag state; never own construction or harvest records.
## Assumption: Area designation considers only currently loaded resources and every mutation is validated by WorldState.

const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const WorldStateScript = preload("res://scripts/simulation/world_state.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")
const ConstructionSiteVisualScript = preload("res://scripts/buildings/construction_site_visual.gd")
const BuildOrderPanelScript = preload("res://scripts/ui/build_order_panel.gd")

const DEFAULT_BUILDING_ID := "campfire"
const AREA_DRAG_THRESHOLD_PIXELS := 6.0

@onready var _chunk_manager: ChunkManager = $ChunkManager
@onready var _resource_label: Label = $CanvasLayer/PanelContainer/MarginContainer/ResourceLabel
@onready var _selected_tile_panel: SelectedTilePanel = $CanvasLayer/SelectedTilePanel
@onready var _colonist_info_panel: PanelContainer = $CanvasLayer/ColonistInfoPanel
@onready var _build_order_panel = $CanvasLayer/BuildOrderPanel
@onready var _colonist_manager: ColonistManager = $ChunkManager/GameplayYSort/ColonistManager

var _world_state
var _tile_selections: Array[Dictionary] = []
var _selected_tile_index: int = 0
var _placement_mode: bool = false
var _harvest_mode: bool = false
var _stockpile_mode: bool = false
var _selected_building_id: String = DEFAULT_BUILDING_ID
var _placement_preview: Node2D
var _placement_result: Dictionary = {}
var _selected_colonist: Colonist
var drag_start_cell: Vector2i = Vector2i.ZERO
var drag_current_cell: Vector2i = Vector2i.ZERO
var is_dragging_harvest_area: bool = false
var is_dragging_stockpile_area: bool = false
var _area_drag_start_screen_position: Vector2 = Vector2.ZERO
var _area_drag_preview: Node2D
var _area_drag_fill: Polygon2D
var _area_drag_outline: Line2D
var _last_harvest_designation_result: Dictionary = {}
var _last_stockpile_zone_result: Dictionary = {}

func _ready() -> void:
	_tile_selections = TerrainConfigRef.get_selectable_terrains()
	_world_state = WorldStateScript.new()
	_world_state.name = "WorldState"
	add_child(_world_state)
	_world_state.resource_total_changed.connect(_on_resource_total_changed)
	_world_state.storage_capacity_changed.connect(_on_storage_capacity_changed)
	_world_state.time_changed.connect(_on_time_changed)
	_world_state.day_phase_changed.connect(_on_day_phase_changed)
	_world_state.set_placement_query(_chunk_manager)
	_chunk_manager.set_world_state(_world_state)
	_colonist_manager.set_world_state(_world_state)
	_colonist_manager.population_replaced.connect(_on_colonist_population_replaced)
	_build_order_panel.building_requested.connect(_on_building_requested)
	_build_order_panel.harvest_mode_requested.connect(_on_harvest_mode_requested)
	_build_order_panel.stockpile_mode_requested.connect(_on_stockpile_mode_requested)
	_build_order_panel.cancel_mode_requested.connect(_cancel_control_mode)
	_create_area_drag_preview()
	_placement_preview = ConstructionSiteVisualScript.new()
	_placement_preview.name = "ConstructionPlacementPreview"
	_placement_preview.z_index = 100
	_placement_preview.visible = false
	add_child(_placement_preview)
	_update_resource_label()
	_selected_tile_panel.setup(_chunk_manager.terrain_layer)
	_update_selected_tile_ui()
	_update_control_mode_ui()

func _process(delta: float) -> void:
	_world_state.advance_time(delta)
	if _placement_mode:
		_update_placement_preview()

func _input(event: InputEvent) -> void:
	## Observe area drags before collision picking. Tiny Harvest releases remain unhandled for exact ResourceNode clicks.
	if not _harvest_mode and not _stockpile_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_viewport().gui_get_hovered_control() == null:
				_begin_area_drag(event.position)
		elif _is_dragging_area():
			var exceeded_threshold: bool = event.position.distance_to(_area_drag_start_screen_position) >= AREA_DRAG_THRESHOLD_PIXELS
			if exceeded_threshold or is_dragging_stockpile_area:
				_finish_area_drag(event.position)
				get_viewport().set_input_as_handled()
			else:
				_clear_area_drag()
	elif event is InputEventMouseMotion and _is_dragging_area():
		_update_area_drag(event.position)

func _on_resource_total_changed(_resource_type: String, _total: int) -> void:
	_update_resource_label()

func _on_storage_capacity_changed(_capacity: int, _stored: int) -> void:
	_update_resource_label()

func _on_time_changed(_day: int, _hour: int, _minute: int) -> void:
	_update_resource_label()

func _on_day_phase_changed(_is_daytime: bool) -> void:
	_update_resource_label()

func _update_resource_label() -> void:
	var phase_label: String = "Day" if _world_state.is_day() else "Night"
	var selected_definition: Dictionary = BuildingDefinitionRef.get_definition(_selected_building_id)
	var selected_name: String = String(selected_definition.get("display_name", _selected_building_id))
	var action_text: String
	if _placement_mode:
		action_text = "Build %s: click to place; right-click/Esc cancels." % selected_name
	elif _harvest_mode:
		action_text = "Harvest: click or drag resources; right-click/Esc cancels."
		if not _last_harvest_designation_result.is_empty():
			var skipped: int = int(_last_harvest_designation_result.get("skipped_already_ordered", 0)) + int(_last_harvest_designation_result.get("skipped_invalid", 0)) + int(_last_harvest_designation_result.get("skipped_depleted", 0))
			action_text += " Last area: %d designated, %d skipped." % [int(_last_harvest_designation_result.get("designated", 0)), skipped]
	elif _stockpile_mode:
		action_text = "Stockpile Zone: drag over valid tiles; right-click/Esc cancels."
		if not _last_stockpile_zone_result.is_empty():
			if bool(_last_stockpile_zone_result.get("ok", false)):
				action_text += " Created stockpile zone: %d cells." % int(_last_stockpile_zone_result.get("cell_count", 0))
			else:
				action_text += " Zone rejected: %s." % String(_last_stockpile_zone_result.get("reason", "invalid"))
	else:
		action_text = "Normal selection. Use Build/Harvest/Stockpile panel or B/H/Z shortcuts."
	_resource_label.text = "Wood: %d\nStone: %d\nFood: %d\nStorage: %d / %d\nTime: %s (%s)\n%s" % [
		_world_state.get_resource_total("wood"),
		_world_state.get_resource_total("stone"),
		_world_state.get_resource_total("food"),
		_world_state.get_stored_resource_total(),
		_world_state.get_storage_capacity(),
		_world_state.get_time_label(),
		phase_label,
		action_text,
	]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				_set_placement_mode(not _placement_mode)
				get_viewport().set_input_as_handled()
			KEY_H:
				_set_harvest_mode(not _harvest_mode)
				get_viewport().set_input_as_handled()
			KEY_Z:
				_set_stockpile_mode(not _stockpile_mode)
				get_viewport().set_input_as_handled()
			KEY_C:
				_attempt_progress_construction()
				get_viewport().set_input_as_handled()
			KEY_X:
				_attempt_cancel_construction()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _placement_mode or _harvest_mode or _stockpile_mode:
					_cancel_control_mode()
					get_viewport().set_input_as_handled()
			KEY_1:
				if _placement_mode:
					_select_building("campfire")
				else:
					_cycle_selected_tile(1)
			KEY_2:
				if _placement_mode:
					_select_building("cabin")
				else:
					_cycle_selected_tile(-1)
			KEY_3:
				if _placement_mode:
					_select_building("storehouse")
	elif event is InputEventMouseButton and event.pressed and not event.is_echo():
		if _placement_mode and event.button_index == MOUSE_BUTTON_LEFT:
			_attempt_place_construction()
			get_viewport().set_input_as_handled()
		elif _placement_mode and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_control_mode()
			get_viewport().set_input_as_handled()
		elif _harvest_mode and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_control_mode()
			get_viewport().set_input_as_handled()
		elif _stockpile_mode and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_control_mode()
			get_viewport().set_input_as_handled()
		elif _harvest_mode and event.button_index == MOUSE_BUTTON_LEFT:
			# Keep harvest presses out of normal selection while leaving them available to ResourceNode picking.
			pass
		elif _stockpile_mode and event.button_index == MOUSE_BUTTON_LEFT:
			# Main observes and commits the stockpile rectangle on release.
			pass
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_world_selection()

func _set_placement_mode(enabled: bool) -> void:
	_placement_mode = enabled
	if enabled:
		_harvest_mode = false
		_stockpile_mode = false
		_clear_area_drag()
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_placement_preview.visible = enabled
	if enabled:
		_update_placement_preview()
	_update_resource_label()
	_update_control_mode_ui()

func _set_harvest_mode(enabled: bool) -> void:
	var entering_mode: bool = enabled and not _harvest_mode
	_harvest_mode = enabled
	_placement_mode = false
	_stockpile_mode = false
	_placement_preview.visible = false
	_clear_area_drag()
	if entering_mode:
		_last_harvest_designation_result.clear()
	_chunk_manager.set_harvest_designation_input_enabled(enabled)
	_update_resource_label()
	_update_control_mode_ui()

func _set_stockpile_mode(enabled: bool) -> void:
	var entering_mode: bool = enabled and not _stockpile_mode
	_stockpile_mode = enabled
	_placement_mode = false
	_harvest_mode = false
	_placement_preview.visible = false
	_clear_area_drag()
	if entering_mode:
		_last_stockpile_zone_result.clear()
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_update_resource_label()
	_update_control_mode_ui()

func _cancel_control_mode() -> void:
	_placement_mode = false
	_harvest_mode = false
	_stockpile_mode = false
	_clear_area_drag()
	_placement_preview.visible = false
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_update_resource_label()
	_update_control_mode_ui()

func _update_control_mode_ui() -> void:
	if _placement_mode:
		var definition: Dictionary = BuildingDefinitionRef.get_definition(_selected_building_id)
		_build_order_panel.set_mode("Build: %s" % String(definition.get("display_name", _selected_building_id)), true)
	elif _harvest_mode:
		_build_order_panel.set_mode("Harvest Designation: click or drag", true)
	elif _stockpile_mode:
		_build_order_panel.set_mode("Stockpile Zone: drag tiles", true)
	else:
		_build_order_panel.set_mode("Normal Selection", false)

func get_control_mode_name() -> String:
	if _placement_mode:
		return "build"
	if _harvest_mode:
		return "harvest"
	if _stockpile_mode:
		return "stockpile"
	return "normal"

func _on_building_requested(building_id: String) -> void:
	_select_building(building_id)
	_set_placement_mode(true)

func _on_harvest_mode_requested() -> void:
	_set_harvest_mode(true)

func _on_stockpile_mode_requested() -> void:
	_set_stockpile_mode(true)

func _create_area_drag_preview() -> void:
	## Transient presentation only; the preview never stores or authorizes harvest orders.
	_area_drag_preview = Node2D.new()
	_area_drag_preview.name = "AreaDesignationPreview"
	_area_drag_preview.z_index = 90
	_area_drag_preview.visible = false
	add_child(_area_drag_preview)
	_area_drag_fill = Polygon2D.new()
	_area_drag_preview.add_child(_area_drag_fill)
	_area_drag_outline = Line2D.new()
	_area_drag_outline.width = 2.0
	_area_drag_outline.antialiased = true
	_area_drag_preview.add_child(_area_drag_outline)

func _begin_area_drag(screen_position: Vector2) -> void:
	_area_drag_start_screen_position = screen_position
	drag_start_cell = _chunk_manager.world_to_cell(_screen_to_world(screen_position))
	drag_current_cell = drag_start_cell
	is_dragging_harvest_area = _harvest_mode
	is_dragging_stockpile_area = _stockpile_mode
	if is_dragging_stockpile_area:
		_area_drag_fill.color = Color(0.18, 0.62, 1.0, 0.18)
		_area_drag_outline.default_color = Color(0.28, 0.76, 1.0, 0.95)
	else:
		_area_drag_fill.color = Color(1.0, 0.78, 0.12, 0.16)
		_area_drag_outline.default_color = Color(1.0, 0.84, 0.22, 0.95)
	_update_area_drag_preview()

func _update_area_drag(screen_position: Vector2) -> void:
	drag_current_cell = _chunk_manager.world_to_cell(_screen_to_world(screen_position))
	_update_area_drag_preview()

func _finish_area_drag(screen_position: Vector2) -> void:
	_update_area_drag(screen_position)
	var cell_rect: Rect2i = _get_area_drag_cell_rect()
	var was_stockpile_drag: bool = is_dragging_stockpile_area
	_clear_area_drag()
	if was_stockpile_drag:
		_last_stockpile_zone_result = _create_stockpile_zone_from_rect(cell_rect)
	else:
		_last_harvest_designation_result = _designate_harvest_resources_in_rect(cell_rect)
	_update_resource_label()

func _clear_area_drag() -> void:
	is_dragging_harvest_area = false
	is_dragging_stockpile_area = false
	if _area_drag_preview != null:
		_area_drag_preview.visible = false

func _is_dragging_area() -> bool:
	return is_dragging_harvest_area or is_dragging_stockpile_area

func _get_area_drag_cell_rect() -> Rect2i:
	var minimum := Vector2i(mini(drag_start_cell.x, drag_current_cell.x), mini(drag_start_cell.y, drag_current_cell.y))
	var maximum := Vector2i(maxi(drag_start_cell.x, drag_current_cell.x), maxi(drag_start_cell.y, drag_current_cell.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

func _update_area_drag_preview() -> void:
	if _area_drag_preview == null or not _is_dragging_area():
		return
	var cell_rect: Rect2i = _get_area_drag_cell_rect()
	var origin: Vector2 = _chunk_manager.get_cell_world_position(cell_rect.position)
	var x_step: Vector2 = _chunk_manager.get_cell_world_position(cell_rect.position + Vector2i.RIGHT) - origin
	var y_step: Vector2 = _chunk_manager.get_cell_world_position(cell_rect.position + Vector2i.DOWN) - origin
	var first: Vector2 = to_local(origin - x_step * 0.5 - y_step * 0.5)
	var second: Vector2 = first + x_step * float(cell_rect.size.x)
	var fourth: Vector2 = first + y_step * float(cell_rect.size.y)
	var third: Vector2 = second + y_step * float(cell_rect.size.y)
	var corners := PackedVector2Array([first, second, third, fourth])
	_area_drag_fill.polygon = corners
	_area_drag_outline.points = PackedVector2Array([first, second, third, fourth, first])
	_area_drag_preview.visible = true

func _create_stockpile_zone_from_rect(cell_rect: Rect2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	for y in range(cell_rect.position.y, cell_rect.end.y):
		for x in range(cell_rect.position.x, cell_rect.end.x):
			cells.append(Vector2i(x, y))
	return _world_state.request_create_stockpile_zone(cells)

func _designate_harvest_resources_in_rect(cell_rect: Rect2i) -> Dictionary:
	## Query presentation-owned loaded resources, but submit every mutation through WorldState.
	var result_counts := {
		"queried": 0,
		"designated": 0,
		"skipped_already_ordered": 0,
		"skipped_invalid": 0,
		"skipped_depleted": 0,
	}
	for resource: Dictionary in _chunk_manager.get_loaded_resources_in_cell_rect(cell_rect):
		result_counts["queried"] += 1
		var result: Dictionary = _world_state.request_designate_harvest(String(resource.get("resource_id", "")))
		if bool(result.get("ok", false)):
			result_counts["designated"] += 1
			continue
		match String(result.get("reason", "")):
			"already_designated":
				result_counts["skipped_already_ordered"] += 1
			"resource_depleted":
				result_counts["skipped_depleted"] += 1
			_:
				result_counts["skipped_invalid"] += 1
	return result_counts

func get_last_harvest_designation_result() -> Dictionary:
	return _last_harvest_designation_result.duplicate(true)

func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_position

func _update_placement_preview() -> void:
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var definition: Dictionary = BuildingDefinitionRef.get_definition(_selected_building_id)
	var visual_metadata: Dictionary = BuildingDefinitionRef.get_visual_metadata(_selected_building_id)
	_placement_result = _world_state.validate_construction_placement(_selected_building_id, target_cell)
	_placement_preview.global_position = _chunk_manager.get_cell_world_position(target_cell) + Vector2(0, -4)
	_placement_preview.configure_preview(
		bool(_placement_result.get("ok", false)),
		_selected_building_id,
		definition.get("footprint", Vector2i.ONE),
		String(visual_metadata.get("construction_visual_id", "generic_scaffold")),
		visual_metadata.get("placeholder_palette", {})
	)

func _attempt_place_construction() -> void:
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var result: Dictionary = _world_state.request_place_construction(_selected_building_id, target_cell)
	if not bool(result.get("ok", false)):
		push_warning("%s placement failed: %s" % [BuildingDefinitionRef.get_definition(_selected_building_id).get("display_name", _selected_building_id), String(result.get("reason", "unknown"))])
	_update_placement_preview()

func _select_building(building_id: String) -> void:
	if not BuildingDefinitionRef.has_definition(building_id):
		push_warning("Cannot select unknown building '%s'." % building_id)
		return
	_selected_building_id = building_id
	if _placement_mode:
		_update_placement_preview()
	_update_resource_label()
	_update_control_mode_ui()

func _attempt_progress_construction() -> void:
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var site: Dictionary = _world_state.get_construction_site_at_cell(target_cell)
	if site.is_empty():
		push_warning("No construction site exists under the cursor.")
		return
	var remaining_progress: float = maxf(float(site.get("build_time", 0.0)) - float(site.get("build_progress", 0.0)), 1.0)
	var result: Dictionary = _world_state.request_progress_construction(String(site.get("site_id", "")), remaining_progress)
	if not bool(result.get("ok", false)):
		push_warning("Construction progress failed: %s" % String(result.get("reason", "unknown")))

func _attempt_cancel_construction() -> void:
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var site: Dictionary = _world_state.get_construction_site_at_cell(target_cell)
	if site.is_empty():
		push_warning("No construction site exists under the cursor.")
		return
	var result: Dictionary = _world_state.request_cancel_construction(String(site.get("site_id", "")))
	if not bool(result.get("ok", false)):
		push_warning("Construction cancellation failed: %s" % String(result.get("reason", "unknown")))
	if _placement_mode:
		_update_placement_preview()

func _cycle_selected_tile(direction: int) -> void:
	_selected_tile_index = wrapi(_selected_tile_index + direction, 0, _tile_selections.size())
	_update_selected_tile_ui()

func _update_selected_tile_ui() -> void:
	var entry: Dictionary = _tile_selections[_selected_tile_index]
	_selected_tile_panel.set_selected_tile(entry)

func _attempt_place_selected_tile() -> void:
	var entry: Dictionary = _tile_selections[_selected_tile_index]
	# BLANK is intentionally a no-op to avoid erasing the ground layer without a wider override/persistence design.
	if String(entry.get("id", "")).is_empty():
		return
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var result: Dictionary = _chunk_manager.request_place_manual_tile(target_cell, String(entry.get("id", "")))
	if not bool(result.get("ok", false)):
		push_warning("Manual tile placement failed: %s" % String(result.get("reason", "unknown")))

func _handle_world_selection() -> void:
	var clicked_colonist: Colonist = _colonist_manager.get_colonist_at_world_position(get_global_mouse_position())
	_set_selected_colonist(clicked_colonist)
	if clicked_colonist == null:
		_attempt_place_selected_tile()

func _set_selected_colonist(colonist: Colonist) -> void:
	if _selected_colonist != null and is_instance_valid(_selected_colonist):
		_selected_colonist.set_selected(false)
	_selected_colonist = colonist
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		_colonist_info_panel.clear_selection()
		return
	_selected_colonist.set_selected(true)
	_colonist_info_panel.display_colonist(_selected_colonist)

func _on_colonist_population_replaced() -> void:
	## Saved UI selection is intentionally excluded; imported populations begin unselected.
	_set_selected_colonist(null)
