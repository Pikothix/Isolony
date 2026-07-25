extends Node2D

## Purpose: Coordinate the playable scene, transient control tools, and requests into simulation authorities.
## Responsibility: Own player input, selection, transient context actions and active-space view coordination, Move requests, Build/Harvest/debug-cliff control modes, and previews while retaining dormant legacy stockpile-zone compatibility state.
## Assumption: Area designation considers only currently loaded resources and every mutation is validated by WorldState.

const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")
const WorldStateScript = preload("res://scripts/simulation/world_state.gd")
const BuildingDefinitionRef = preload("res://scripts/buildings/building_definition.gd")
const ConstructionSiteVisualScript = preload("res://scripts/buildings/construction_site_visual.gd")
const CaveDefinitionRef = preload("res://scripts/interiors/cave_definition.gd")

const DEFAULT_BUILDING_ID := "campfire"
const AREA_DRAG_THRESHOLD_PIXELS := 6.0
const FIRST_CAVE_SEALED_CANDIDATE_ID := CaveDefinitionRef.FIRST_SEALED_CAVE_CANDIDATE
const DEBUG_RIGHT_CLICK_CONTEXT := false

@onready var _chunk_manager: ChunkManager = $ChunkManager
@onready var _resource_label: Label = $CanvasLayer/PanelContainer/MarginContainer/ResourceLabel
@onready var _selected_tile_panel: SelectedTilePanel = $CanvasLayer/SelectedTilePanel
@onready var _colonist_info_panel: PanelContainer = $CanvasLayer/ColonistInfoPanel
@onready var _storage_inspector_panel: PanelContainer = $CanvasLayer/StorageInspectorPanel
@onready var _resource_inspector_panel: PanelContainer = $CanvasLayer/ResourceInspectorPanel
@onready var _bottom_toolbar: PanelContainer = $CanvasLayer/BottomToolbar
@onready var _bottom_ui_controller: BottomUiController = $CanvasLayer/BottomUiController
@onready var _work_priority_table: PanelContainer = $CanvasLayer/WorkPriorityPanel
@onready var _render_debug_panel: RenderDebugPanel = $CanvasLayer/RenderDebugPanel
@onready var _escape_menu: PanelContainer = $CanvasLayer/EscapeMenu
@onready var _escape_resume_button: Button = $CanvasLayer/EscapeMenu/MarginContainer/VBoxContainer/ResumeButton
@onready var _escape_dawn_button: Button = $CanvasLayer/EscapeMenu/MarginContainer/VBoxContainer/DebugTimeButtons/DawnButton
@onready var _escape_noon_button: Button = $CanvasLayer/EscapeMenu/MarginContainer/VBoxContainer/DebugTimeButtons/NoonButton
@onready var _escape_dusk_button: Button = $CanvasLayer/EscapeMenu/MarginContainer/VBoxContainer/DebugTimeButtons/DuskButton
@onready var _escape_midnight_button: Button = $CanvasLayer/EscapeMenu/MarginContainer/VBoxContainer/DebugTimeButtons/MidnightButton
@onready var _colonist_manager: ColonistManager = $ChunkManager/GameplayYSort/ColonistManager
@onready var _camera: Camera2D = $Camera2D

var _world_state
var _tile_selections: Array[Dictionary] = []
var _selected_tile_index: int = 0
var _placement_mode: bool = false
var _harvest_mode: bool = false
var _stockpile_mode: bool = false
var _debug_cliff_mode: bool = false
var _selected_building_id: String = DEFAULT_BUILDING_ID
var _placement_preview: Node2D
var _placement_result: Dictionary = {}
var _selected_colonist: Colonist
var _selected_storage_id: String = ""
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
var _first_cave_surface_connection_cell: Vector2i = Vector2i.ZERO
var _context_menu: PopupMenu
var _context_actions: Array[Dictionary] = []
var _hover_inspection: Dictionary = {}
var _hover_inspection_key: String = ""
var _escape_menu_previous_speed_mode := ""

func _ready() -> void:
	_tile_selections = TerrainConfigRef.get_selectable_terrains()
	_world_state = WorldStateScript.new()
	_world_state.name = "WorldState"
	add_child(_world_state)
	_world_state.resource_total_changed.connect(_on_resource_total_changed)
	_world_state.storage_capacity_changed.connect(_on_storage_capacity_changed)
	_world_state.time_changed.connect(_on_time_changed)
	_world_state.day_phase_changed.connect(_on_day_phase_changed)
	_world_state.time_speed_changed.connect(_on_time_speed_changed)
	_world_state.set_placement_query(_chunk_manager)
	_chunk_manager.set_world_state(_world_state)
	_chunk_manager.resource_inspection_requested.connect(_on_resource_inspection_requested)
	_colonist_manager.set_world_state(_world_state)
	_work_priority_table.setup(_colonist_manager)
	_colonist_manager.population_replaced.connect(_on_colonist_population_replaced)
	_bottom_toolbar.building_requested.connect(_on_building_requested)
	_bottom_toolbar.harvest_mode_requested.connect(_on_harvest_mode_requested)
	_bottom_toolbar.cancel_mode_requested.connect(_cancel_control_mode)
	_bottom_toolbar.time_speed_requested.connect(_on_time_speed_requested)
	_escape_resume_button.pressed.connect(_close_escape_menu)
	_escape_dawn_button.pressed.connect(_request_debug_time_skip.bind(6, 0))
	_escape_noon_button.pressed.connect(_request_debug_time_skip.bind(12, 0))
	_escape_dusk_button.pressed.connect(_request_debug_time_skip.bind(18, 0))
	_escape_midnight_button.pressed.connect(_request_debug_time_skip.bind(0, 0))
	_bottom_toolbar.set_time_speed_mode(_world_state.get_time_speed_mode())
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
	_context_menu = PopupMenu.new()
	_context_menu.name = "WorldContextMenu"
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	call_deferred("ensure_initial_cave_interior")

func _process(delta: float) -> void:
	_world_state.advance_time(delta)
	_update_hover_inspection()
	if _placement_mode:
		_update_placement_preview()
	if _debug_cliff_mode:
		_update_debug_cliff_preview()

func _input(event: InputEvent) -> void:
	## Observe area drags before collision picking. Tiny Harvest releases remain unhandled for exact ResourceNode clicks.
	if not _harvest_mode and not _stockpile_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_viewport().gui_get_hovered_control() == null:
				_resource_inspector_panel.clear_selection()
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
	_refresh_selected_storage_inspector()

func _on_time_changed(_day: int, _hour: int, _minute: int) -> void:
	_update_resource_label()

func _on_day_phase_changed(_is_daytime: bool) -> void:
	_update_resource_label()

func _on_time_speed_changed(mode: String, _time_scale: float) -> void:
	_bottom_toolbar.set_time_speed_mode(mode)

func _on_time_speed_requested(mode: String) -> void:
	_world_state.request_set_time_speed(mode)


func _open_escape_menu() -> void:
	if _escape_menu.visible:
		return
	_escape_menu_previous_speed_mode = _world_state.get_time_speed_mode()
	_world_state.request_set_time_speed("pause")
	_escape_menu.visible = true


func _close_escape_menu() -> void:
	if not _escape_menu.visible:
		return
	_escape_menu.visible = false
	if not _escape_menu_previous_speed_mode.is_empty():
		_world_state.request_set_time_speed(_escape_menu_previous_speed_mode)
	_escape_menu_previous_speed_mode = ""


func _request_debug_time_skip(hour: int, minute: int) -> void:
	## Debug UI requests an authoritative clock teleport. It deliberately does not simulate elapsed gameplay.
	var result: Dictionary = _world_state.request_debug_set_time_of_day(hour, minute)
	if not bool(result.get("ok", false)):
		push_warning("Debug time skip failed: %s" % String(result.get("reason", "unknown")))

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
	elif _debug_cliff_mode:
		action_text = "Debug Cliff: left-click translucent, right-click solid; P/Esc exits."
	else:
		action_text = "Normal selection. Right-click a Mine Entrance to travel."
		var cave_candidate: Dictionary = CaveDefinitionRef.get_sealed_cave_candidate(FIRST_CAVE_SEALED_CANDIDATE_ID)
		var cave_connection: Dictionary = _world_state.get_connection(String(cave_candidate.get("connection_id", "")))
		if not cave_connection.is_empty():
			var active_world_space_id: String = _chunk_manager.get_active_world_space_id()
			var endpoint: Vector2i = cave_connection.get("from_cell", Vector2i.ZERO) if String(cave_connection.get("from_world_space_id", "")) == active_world_space_id else cave_connection.get("to_cell", Vector2i.ZERO)
			action_text += " Active endpoint: (%d, %d)." % [endpoint.x, endpoint.y]
		else:
			var sealed_candidate: Dictionary = _world_state.get_sealed_cave_candidate(FIRST_CAVE_SEALED_CANDIDATE_ID)
			if not sealed_candidate.is_empty():
				var candidate_cell: Vector2i = sealed_candidate.get("surface_cell", Vector2i.ZERO)
				action_text += " Sealed mine: (%d, %d)." % [candidate_cell.x, candidate_cell.y]
	_resource_label.text = "Wood: %d\nStone: %d\nFood: %d\nStorage: %d / %d\nTime: %s (%s)\n%s\n%s" % [
		_world_state.get_resource_total("wood"),
		_world_state.get_resource_total("stone"),
		_world_state.get_resource_total("food"),
		_world_state.get_stored_resource_total(),
		_world_state.get_storage_capacity(),
		_world_state.get_time_label(),
		phase_label,
		action_text,
		_format_hover_inspection(_hover_inspection),
	]

func _update_hover_inspection() -> void:
	var snapshot: Dictionary = _chunk_manager.get_hover_inspection_snapshot(_screen_to_world(get_viewport().get_mouse_position()))
	var snapshot_key: String = var_to_str(snapshot)
	if snapshot_key == _hover_inspection_key:
		return
	_hover_inspection = snapshot
	_hover_inspection_key = snapshot_key
	_update_resource_label()

func _format_hover_inspection(snapshot: Dictionary) -> String:
	if snapshot.is_empty() or not bool(snapshot.get("ok", false)):
		return "Hover: none"
	var cell: Vector2i = snapshot.get("cell", Vector2i.ZERO)
	var authority: Dictionary = snapshot.get("authority", {})
	var lines: Array[String] = [
		"Hover:",
		"Space: %s" % String(snapshot.get("world_space_id", "")),
		"Cell: (%d, %d)" % [cell.x, cell.y],
		"Terrain: %s (%s)" % [String(snapshot.get("terrain_id", "")), String(snapshot.get("terrain_name", ""))],
		"Elevation: %d" % int(snapshot.get("elevation", 0)),
		"Walkable: %s" % _format_bool(bool(snapshot.get("walkable", false))),
		"Mineable/Diggable: %s/%s" % [
			_format_bool(bool(snapshot.get("mineable", false))),
			_format_bool(bool(authority.get("diggable", false))),
		],
	]
	var construction: Dictionary = authority.get("construction", {})
	if not construction.is_empty():
		var building_id: String = String(construction.get("building_id", ""))
		var building_name: String = String(BuildingDefinitionRef.get_definition(building_id).get("display_name", building_id))
		lines.append("Building: %s (%s, %s)" % [String(construction.get("site_id", "")), building_id, building_name])
	var stockpile_zone: Dictionary = authority.get("stockpile_zone", {})
	if not stockpile_zone.is_empty():
		lines.append("Stockpile: %s" % String(stockpile_zone.get("zone_id", "")))
	var ground_items: Array = authority.get("ground_items", [])
	if not ground_items.is_empty():
		var item: Dictionary = ground_items[0]
		var suffix: String = " +%d" % (ground_items.size() - 1) if ground_items.size() > 1 else ""
		lines.append("Ground: %s x%d (%s)%s" % [
			String(item.get("resource_type", "")),
			int(item.get("amount", 0)),
			String(item.get("item_id", "")),
			suffix,
		])
	var resource_node: Dictionary = snapshot.get("resource_node", {})
	if not resource_node.is_empty():
		lines.append("Resource: %s %s x%d (%s)" % [
			String(resource_node.get("display_name", "Resource")),
			String(resource_node.get("resource_type", "")),
			int(resource_node.get("yield_amount", 0)),
			String(resource_node.get("resource_id", "")),
		])
	var cave: Dictionary = authority.get("cave", {})
	if not cave.is_empty():
		lines.append("Cave: %s (%s)" % [String(cave.get("kind", "")), String(cave.get("candidate_id", ""))])
	return "\n".join(lines)

func _format_bool(value: bool) -> String:
	return "yes" if value else "no"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_world_state.request_toggle_time_pause()
				get_viewport().set_input_as_handled()
			KEY_P:
				_set_debug_cliff_mode(not _debug_cliff_mode)
				get_viewport().set_input_as_handled()
			KEY_B:
				_set_placement_mode(not _placement_mode)
				get_viewport().set_input_as_handled()
			KEY_H:
				_set_harvest_mode(not _harvest_mode)
				get_viewport().set_input_as_handled()
			KEY_C:
				_attempt_progress_construction()
				get_viewport().set_input_as_handled()
			KEY_X:
				_attempt_cancel_construction()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if _context_menu != null and _context_menu.visible:
					_context_menu.hide()
					get_viewport().set_input_as_handled()
				elif _placement_mode or _harvest_mode or _stockpile_mode or _debug_cliff_mode:
					_cancel_control_mode()
					get_viewport().set_input_as_handled()
				elif _escape_menu.visible:
					_close_escape_menu()
					get_viewport().set_input_as_handled()
				else:
					_open_escape_menu()
					get_viewport().set_input_as_handled()
			KEY_1:
				if _placement_mode:
					_select_building("campfire")
					get_viewport().set_input_as_handled()
				elif _handle_developer_number_shortcut(event.keycode):
					get_viewport().set_input_as_handled()
				else:
					_cycle_selected_tile(1)
			KEY_2:
				if _placement_mode:
					_select_building("cabin")
					get_viewport().set_input_as_handled()
				elif _handle_developer_number_shortcut(event.keycode):
					get_viewport().set_input_as_handled()
				else:
					_cycle_selected_tile(-1)
			KEY_3:
				if _placement_mode:
					_select_building("storehouse")
					get_viewport().set_input_as_handled()
			KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
				if not _placement_mode and _handle_developer_number_shortcut(event.keycode):
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not event.is_echo():
		if _context_menu != null and _context_menu.visible:
			_context_menu.hide()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_debug_right_click_context("received", event.position, {})
		if _debug_cliff_mode and event.button_index == MOUSE_BUTTON_LEFT:
			_place_debug_cliff_marker(false)
			get_viewport().set_input_as_handled()
		elif _debug_cliff_mode and event.button_index == MOUSE_BUTTON_RIGHT:
			_place_debug_cliff_marker(true)
			get_viewport().set_input_as_handled()
		elif _placement_mode and event.button_index == MOUSE_BUTTON_LEFT:
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
		elif event.button_index == MOUSE_BUTTON_RIGHT and _try_open_connection_context_menu(event.position):
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _try_open_mining_context_menu(event.position):
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _selected_colonist != null and is_instance_valid(_selected_colonist):
			_request_selected_colonist_move(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_world_selection()

func _set_placement_mode(enabled: bool) -> void:
	_placement_mode = enabled
	if enabled:
		_bottom_ui_controller.close_current_drawer()
		_harvest_mode = false
		_stockpile_mode = false
		_exit_debug_cliff_mode()
		_clear_area_drag()
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_placement_preview.visible = enabled
	if enabled:
		_update_placement_preview()
	_update_resource_label()
	_update_control_mode_ui()

func _handle_developer_number_shortcut(keycode: Key) -> bool:
	## Developer shortcuts are intentionally scene-local requests; they do not mutate simulation state.
	match keycode:
		KEY_1:
			_request_developer_view_world_space(ChunkManager.SURFACE_WORLD_SPACE_ID)
			return true
		KEY_2:
			var cave_candidate: Dictionary = CaveDefinitionRef.get_sealed_cave_candidate(FIRST_CAVE_SEALED_CANDIDATE_ID)
			_request_developer_view_world_space(String(cave_candidate.get("world_space_id", "")))
			return true
		KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			# Reserved placeholders: pathfinding, job, reachability, lighting, performance, and AI debug overlays.
			return true
		KEY_0:
			_clear_developer_debug_overlays()
			return true
	return false

func _request_developer_view_world_space(destination_world_space_id: String) -> void:
	if _chunk_manager.get_active_world_space_id() == destination_world_space_id:
		return
	var cave_candidate: Dictionary = CaveDefinitionRef.get_sealed_cave_candidate(FIRST_CAVE_SEALED_CANDIDATE_ID)
	var connection_id: String = String(cave_candidate.get("connection_id", ""))
	var connection: Dictionary = _world_state.get_connection(connection_id)
	if connection.is_empty():
		var setup_result: Dictionary = ensure_initial_cave_interior()
		if not bool(setup_result.get("ok", false)):
			push_warning("Developer view shortcut failed: %s" % String(setup_result.get("reason", "unknown")))
			return
		connection = _world_state.get_connection(connection_id)
	if connection.is_empty():
		push_warning("Developer view shortcut failed: missing cave connection.")
		return
	var active_world_space_id: String = _chunk_manager.get_active_world_space_id()
	var source_cell: Vector2i = Vector2i.ZERO
	if String(connection.get("from_world_space_id", "")) == active_world_space_id and String(connection.get("to_world_space_id", "")) == destination_world_space_id:
		source_cell = connection.get("from_cell", Vector2i.ZERO)
	elif String(connection.get("to_world_space_id", "")) == active_world_space_id and String(connection.get("from_world_space_id", "")) == destination_world_space_id:
		source_cell = connection.get("to_cell", Vector2i.ZERO)
	else:
		push_warning("Developer view shortcut failed: no connection from %s to %s." % [active_world_space_id, destination_world_space_id])
		return
	var result: Dictionary = request_player_view_connection_use(connection_id, active_world_space_id, source_cell)
	if not bool(result.get("ok", false)):
		push_warning("Developer view shortcut failed: %s" % String(result.get("reason", "unknown")))

func _clear_developer_debug_overlays() -> void:
	_exit_debug_cliff_mode()
	if _render_debug_panel != null:
		_render_debug_panel.visible = false

func _set_harvest_mode(enabled: bool) -> void:
	var entering_mode: bool = enabled and not _harvest_mode
	_harvest_mode = enabled
	_placement_mode = false
	_stockpile_mode = false
	_exit_debug_cliff_mode()
	_placement_preview.visible = false
	_clear_area_drag()
	if entering_mode:
		_bottom_ui_controller.close_current_drawer()
		_last_harvest_designation_result.clear()
	_chunk_manager.set_harvest_designation_input_enabled(enabled)
	_update_resource_label()
	_update_control_mode_ui()

func _set_stockpile_mode(enabled: bool) -> void:
	var entering_mode: bool = enabled and not _stockpile_mode
	_stockpile_mode = enabled
	_placement_mode = false
	_harvest_mode = false
	_exit_debug_cliff_mode()
	_placement_preview.visible = false
	_clear_area_drag()
	if entering_mode:
		_bottom_ui_controller.close_current_drawer()
		_last_stockpile_zone_result.clear()
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_update_resource_label()
	_update_control_mode_ui()

func _cancel_control_mode() -> void:
	_placement_mode = false
	_harvest_mode = false
	_stockpile_mode = false
	_exit_debug_cliff_mode()
	_clear_area_drag()
	_placement_preview.visible = false
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_update_resource_label()
	_update_control_mode_ui()

func _update_control_mode_ui() -> void:
	if _placement_mode:
		var definition: Dictionary = BuildingDefinitionRef.get_definition(_selected_building_id)
		_bottom_toolbar.set_mode("Build: %s" % String(definition.get("display_name", _selected_building_id)), true)
	elif _harvest_mode:
		_bottom_toolbar.set_mode("Harvest Designation: click or drag", true)
	elif _stockpile_mode:
		_bottom_toolbar.set_mode("Stockpile Zone: drag tiles", true)
	elif _debug_cliff_mode:
		_bottom_toolbar.set_mode("Debug Cliff: inspect elevation", true)
	else:
		_bottom_toolbar.set_mode("Normal Selection", false)

func get_control_mode_name() -> String:
	if _placement_mode:
		return "build"
	if _harvest_mode:
		return "harvest"
	if _stockpile_mode:
		return "stockpile"
	if _debug_cliff_mode:
		return "debug_cliff"
	return "normal"

func _set_debug_cliff_mode(enabled: bool) -> void:
	if not enabled:
		_exit_debug_cliff_mode()
		_update_resource_label()
		_update_control_mode_ui()
		return
	_placement_mode = false
	_harvest_mode = false
	_stockpile_mode = false
	_clear_area_drag()
	_placement_preview.visible = false
	_chunk_manager.set_harvest_designation_input_enabled(false)
	_debug_cliff_mode = true
	_update_debug_cliff_preview()
	_update_resource_label()
	_update_control_mode_ui()

func _exit_debug_cliff_mode() -> void:
	_debug_cliff_mode = false
	_chunk_manager.clear_debug_elevation_preview()

func _update_debug_cliff_preview() -> void:
	var target_cell: Vector2i = _chunk_manager.get_debug_elevation_cell_at_world_position(get_global_mouse_position())
	_chunk_manager.set_debug_elevation_preview(target_cell, true)

func _place_debug_cliff_marker(solid: bool) -> void:
	var target_cell: Vector2i = _chunk_manager.get_debug_elevation_cell_at_world_position(get_global_mouse_position())
	if not _chunk_manager.place_debug_elevation_marker(target_cell, solid):
		push_warning("Debug elevation marker requires a loaded cell.")

func get_selected_building_id() -> String:
	return _selected_building_id

func _on_building_requested(building_id: String) -> void:
	_select_building(building_id)
	_set_placement_mode(true)

func _on_harvest_mode_requested() -> void:
	_set_harvest_mode(true)

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
	_placement_preview.global_position = _chunk_manager.get_cell_visual_world_position(target_cell)
	_placement_preview.configure_preview(
		bool(_placement_result.get("ok", false)),
		_selected_building_id,
		definition.get("footprint", Vector2i.ONE),
		String(visual_metadata.get("construction_visual_id", "generic_scaffold")),
		visual_metadata.get("placeholder_palette", {})
	)

func _attempt_place_construction() -> void:
	var target_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	var result: Dictionary = _request_place_selected_building_at_cell(target_cell)
	if not bool(result.get("ok", false)):
		push_warning("%s placement failed: %s" % [BuildingDefinitionRef.get_definition(_selected_building_id).get("display_name", _selected_building_id), String(result.get("reason", "unknown"))])
	_update_placement_preview()

func _request_place_selected_building_at_cell(target_cell: Vector2i) -> Dictionary:
	## Main routes transient placement intent; WorldState remains the sole mutation authority.
	return _world_state.request_place_construction(_selected_building_id, target_cell)

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
	# ResourceNode picking occurs on the matching release. Clearing here makes
	# empty-terrain clicks dismiss the panel without competing for that release.
	_resource_inspector_panel.clear_selection()
	var clicked_colonist: Colonist = _colonist_manager.get_colonist_at_world_position(get_global_mouse_position())
	if clicked_colonist != null:
		_set_selected_colonist(clicked_colonist)
		return
	_set_selected_colonist(null)
	var selected_cell: Vector2i = _chunk_manager.world_to_cell(get_global_mouse_position())
	if _select_storage_at_cell(selected_cell):
		return
	_attempt_place_selected_tile()


func _on_resource_inspection_requested(inspection_data: Dictionary) -> void:
	_resource_inspector_panel.display_resource(inspection_data)

func _request_selected_colonist_move(screen_position: Vector2) -> Dictionary:
	## Main translates presentation input; the selected Colonist owns validation and transient command state.
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		return {"ok": false, "reason": "no_selected_colonist"}
	if _selected_colonist.current_world_space_id != _chunk_manager.get_active_world_space_id():
		return {"ok": false, "reason": "selected_colonist_not_in_active_world_space"}
	var destination_cell: Vector2i = _chunk_manager.world_to_cell(_screen_to_world(screen_position))
	return _selected_colonist.request_manual_move(destination_cell)

func ensure_initial_cave_interior() -> Dictionary:
	## Main supplies authored setup constants; WorldState owns sealed state, interiors, and topology records.
	if _world_state == null:
		return {"ok": false, "reason": "world_state_unavailable"}
	var cave_candidate: Dictionary = CaveDefinitionRef.get_sealed_cave_candidate(FIRST_CAVE_SEALED_CANDIDATE_ID)
	if cave_candidate.is_empty():
		return {"ok": false, "reason": "missing_sealed_cave_candidate_definition"}
	var interior_id: String = String(cave_candidate.get("interior_id", ""))
	var connection_id: String = String(cave_candidate.get("connection_id", ""))
	if _world_state.has_interior(interior_id) and _world_state.has_connection(connection_id):
		return {"ok": true, "reason": "already_registered"}
	var existing_interior: Dictionary = _world_state.get_interior(interior_id)
	if not existing_interior.is_empty() and bool(existing_interior.get("enabled", false)) and bool(existing_interior.get("open", false)):
		var connection_result: Dictionary = _register_cave_connection(cave_candidate, existing_interior)
		_update_resource_label()
		return connection_result
	if not _world_state.has_interior(interior_id):
		var candidate_cell: Vector2i = _resolve_sealed_cave_candidate_cell(cave_candidate)
		if candidate_cell == Vector2i(2147483647, 2147483647):
			return {"ok": false, "reason": "sealed_cave_candidate_unavailable"}
		_first_cave_surface_connection_cell = candidate_cell
		var interior_result: Dictionary = _world_state.request_register_interior(
			interior_id,
			String(cave_candidate.get("interior_type", "")),
			String(cave_candidate.get("world_space_id", "")),
			_first_cave_surface_connection_cell,
			cave_candidate.get("interior_entrance_cell", Vector2i.ZERO),
			false,
			false
		)
		if not bool(interior_result.get("ok", false)):
			_update_resource_label()
			return interior_result
	var interior: Dictionary = _world_state.get_interior(interior_id)
	var candidate_result: Dictionary = _world_state.request_register_sealed_cave_candidate(
		String(cave_candidate.get("candidate_id", "")),
		interior_id,
		connection_id,
		String(cave_candidate.get("connection_type", "")),
		interior.get("surface_entrance_cell", _first_cave_surface_connection_cell)
	)
	if not bool(candidate_result.get("ok", false)):
		push_warning("Sealed cave setup failed: %s" % String(candidate_result.get("reason", "unknown")))
	_update_resource_label()
	return candidate_result

func _register_cave_connection(cave_candidate: Dictionary, interior: Dictionary) -> Dictionary:
	var connection_id: String = String(cave_candidate.get("connection_id", ""))
	if _world_state.has_connection(connection_id):
		return {"ok": true, "reason": "connection_already_registered"}
	return _world_state.request_register_connection(
		connection_id,
		String(cave_candidate.get("connection_type", "")),
		ChunkManager.SURFACE_WORLD_SPACE_ID,
		interior.get("surface_entrance_cell", _first_cave_surface_connection_cell),
		String(interior.get("world_space_id", cave_candidate.get("world_space_id", ""))),
		interior.get("interior_entrance_cell", cave_candidate.get("interior_entrance_cell", Vector2i.ZERO)),
		true,
		true
	)

func _resolve_sealed_cave_candidate_cell(cave_candidate: Dictionary) -> Vector2i:
	var invalid_cell := Vector2i(2147483647, 2147483647)
	if cave_candidate.has("surface_cell"):
		var fixed_cell: Vector2i = cave_candidate.get("surface_cell", invalid_cell)
		var fixed_validation: Dictionary = _world_state.validate_mining_designation(fixed_cell, ChunkManager.SURFACE_WORLD_SPACE_ID, false)
		var fixed_tile_info: Dictionary = fixed_validation.get("tile_info", {})
		return fixed_cell if bool(fixed_validation.get("ok", false)) and String(fixed_tile_info.get("terrain", "")) == "ROCK_WALL" else invalid_cell
	var search_origin: Vector2i = cave_candidate.get("surface_search_origin", Vector2i.ZERO)
	var search_radius: int = int(cave_candidate.get("surface_search_radius", 0))
	for radius in range(0, search_radius + 1):
		for y_offset in range(-radius, radius + 1):
			for x_offset in range(-radius, radius + 1):
				if maxi(absi(x_offset), absi(y_offset)) != radius:
					continue
				var cell: Vector2i = search_origin + Vector2i(x_offset, y_offset)
				var validation: Dictionary = _world_state.validate_mining_designation(cell, ChunkManager.SURFACE_WORLD_SPACE_ID, false)
				var tile_info: Dictionary = validation.get("tile_info", {})
				if bool(validation.get("ok", false)) and String(tile_info.get("terrain", "")) == "ROCK_WALL":
					return cell
	return invalid_cell

func request_connection_context_at_world_position(world_position: Vector2, screen_position: Vector2) -> Dictionary:
	## Convert one presentation hit into generic transient menu actions; topology remains read-only here.
	var marker: Dictionary = _chunk_manager.get_connection_marker_at_world_position(world_position)
	if marker.is_empty():
		return {"ok": false, "reason": "no_context_object"}
	var action_label: String = String(marker.get("action_label", ""))
	if action_label.is_empty():
		return {"ok": false, "reason": "no_context_actions"}
	var actions: Array[Dictionary] = []
	if _selected_colonist != null and is_instance_valid(_selected_colonist) and _selected_colonist.current_world_space_id == String(marker.get("world_space_id", "")):
		actions.append({
			"label": action_label,
			"action": "selected_colonist_use_connection",
			"payload": {
				"connection_id": String(marker.get("connection_id", "")),
				"source_world_space_id": String(marker.get("world_space_id", "")),
				"source_cell": marker.get("cell", Vector2i.ZERO),
			},
		})
	var view_label: String = "View Surface" if bool(marker.get("is_cave_exit", false)) else "View Mine"
	actions.append({
		"label": view_label,
		"action": "switch_player_view_through_connection",
		"payload": {
			"connection_id": String(marker.get("connection_id", "")),
			"source_world_space_id": String(marker.get("world_space_id", "")),
			"source_cell": marker.get("cell", Vector2i.ZERO),
		},
	})
	_open_context_menu(screen_position, actions)
	return {"ok": true, "reason": "context_menu_opened", "actions": get_context_menu_action_labels()}

func request_mining_context_at_world_position(world_position: Vector2, screen_position: Vector2) -> Dictionary:
	## UI exposes designation intent only; WorldState validates and owns the resulting mining order.
	if _chunk_manager.get_active_world_space_id() != ChunkManager.SURFACE_WORLD_SPACE_ID:
		return {"ok": false, "reason": "unsupported_world_space_id"}
	var target: Dictionary = _get_visible_diggable_surface_cell(world_position)
	if not bool(target.get("ok", false)):
		return target
	var cell: Vector2i = target.get("cell", Vector2i.ZERO)
	_open_context_menu(screen_position, [{
		"label": "Dig",
		"action": "designate_mining",
		"payload": {
			"world_space_id": ChunkManager.SURFACE_WORLD_SPACE_ID,
			"cell": cell,
		},
	}])
	return {"ok": true, "reason": "context_menu_opened", "actions": get_context_menu_action_labels()}

func _get_visible_diggable_surface_cell(world_position: Vector2) -> Dictionary:
	var candidates: Array[Vector2i] = _chunk_manager.get_visible_terrain_cells_at_world_position(world_position, ChunkManager.SURFACE_WORLD_SPACE_ID)
	var first_rejection: Dictionary = {"ok": false, "reason": "no_visible_terrain_candidate", "cell": _chunk_manager.world_to_cell(world_position)}
	for candidate: Vector2i in candidates:
		var validation: Dictionary = _world_state.validate_mining_designation(candidate, ChunkManager.SURFACE_WORLD_SPACE_ID, true)
		validation["cell"] = candidate
		if bool(validation.get("ok", false)):
			return validation
		if String(first_rejection.get("reason", "")) == "no_visible_terrain_candidate":
			first_rejection = validation
	return first_rejection

func is_context_menu_open() -> bool:
	return _context_menu != null and _context_menu.visible

func get_context_menu_action_labels() -> Array[String]:
	var labels: Array[String] = []
	for action: Dictionary in _context_actions:
		labels.append(String(action.get("label", "")))
	return labels

func activate_context_menu_action(action_id: int) -> Dictionary:
	## Shared by PopupMenu signals and focused validation; action routing remains in Main.
	if action_id < 0 or action_id >= _context_actions.size():
		return {"ok": false, "reason": "unknown_context_action"}
	var action: Dictionary = _context_actions[action_id]
	if _context_menu != null:
		_context_menu.hide()
	match String(action.get("action", "")):
		"selected_colonist_use_connection":
			var payload: Dictionary = action.get("payload", {})
			return request_selected_colonist_connection_use(
				String(payload.get("connection_id", "")),
				String(payload.get("source_world_space_id", "")),
				payload.get("source_cell", Vector2i.ZERO)
			)
		"switch_player_view_through_connection":
			var payload: Dictionary = action.get("payload", {})
			return request_player_view_connection_use(
				String(payload.get("connection_id", "")),
				String(payload.get("source_world_space_id", "")),
				payload.get("source_cell", Vector2i.ZERO)
			)
		"designate_mining":
			var payload: Dictionary = action.get("payload", {})
			return request_designate_mining(
				payload.get("cell", Vector2i.ZERO),
				String(payload.get("world_space_id", ChunkManager.SURFACE_WORLD_SPACE_ID))
			)
	return {"ok": false, "reason": "unsupported_context_action"}

func request_designate_mining(cell: Vector2i, world_space_id: String = ChunkManager.SURFACE_WORLD_SPACE_ID) -> Dictionary:
	if world_space_id != _chunk_manager.get_active_world_space_id():
		return {"ok": false, "reason": "inactive_world_space"}
	var result: Dictionary = _world_state.request_designate_mining(cell, world_space_id)
	if bool(result.get("ok", false)):
		_update_resource_label()
	return result

func request_selected_colonist_connection_use(connection_id: String, source_world_space_id: String, source_cell: Vector2i) -> Dictionary:
	## UI asks the selected colonist to use topology; the colonist moves locally and WorldState validates the endpoint transition.
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		return {"ok": false, "reason": "no_selected_colonist"}
	if source_world_space_id != _chunk_manager.get_active_world_space_id():
		return {"ok": false, "reason": "inactive_source_world_space"}
	if _selected_colonist.current_world_space_id != source_world_space_id:
		return {"ok": false, "reason": "selected_colonist_not_in_source_world_space"}
	var connection: Dictionary = _world_state.get_connection(connection_id)
	if connection.is_empty():
		return {"ok": false, "reason": "connection_unavailable"}
	if not _connection_has_endpoint(connection, source_world_space_id, source_cell):
		return {"ok": false, "reason": "source_not_connection_endpoint"}
	var result: Dictionary = _selected_colonist.request_use_world_space_connection(connection_id)
	if bool(result.get("ok", false)):
		_update_resource_label()
		_colonist_info_panel.display_colonist(_selected_colonist)
	return result

func request_player_view_connection_use(connection_id: String, source_world_space_id: String, source_cell: Vector2i) -> Dictionary:
	## Player/camera view switching never mutates colonist WorldSpace ownership.
	if source_world_space_id != _chunk_manager.get_active_world_space_id():
		return {"ok": false, "reason": "inactive_source_world_space"}
	var connection: Dictionary = _world_state.get_connection(connection_id)
	if connection.is_empty():
		return {"ok": false, "reason": "connection_unavailable"}
	if not bool(connection.get("enabled", false)):
		return {"ok": false, "reason": "connection_disabled"}
	var destination_world_space_id: String = ""
	var destination_cell: Vector2i = Vector2i.ZERO
	if String(connection.get("from_world_space_id", "")) == source_world_space_id and connection.get("from_cell", Vector2i.ZERO) == source_cell:
		destination_world_space_id = String(connection.get("to_world_space_id", ""))
		destination_cell = connection.get("to_cell", Vector2i.ZERO)
	elif bool(connection.get("bidirectional", false)) and String(connection.get("to_world_space_id", "")) == source_world_space_id and connection.get("to_cell", Vector2i.ZERO) == source_cell:
		destination_world_space_id = String(connection.get("from_world_space_id", ""))
		destination_cell = connection.get("from_cell", Vector2i.ZERO)
	else:
		return {"ok": false, "reason": "source_not_connection_endpoint"}
	if not _chunk_manager.is_world_space_supported(destination_world_space_id):
		return {"ok": false, "reason": "unsupported_destination_world_space"}
	_camera.global_position = _chunk_manager.get_cell_world_position(destination_cell)
	if not _chunk_manager.set_active_world_space_id(destination_world_space_id):
		return {"ok": false, "reason": "active_world_space_switch_failed"}
	_cancel_control_mode()
	_colonist_manager.refresh_active_world_space_visibility()
	_set_selected_colonist(null)
	_update_resource_label()
	return {
		"ok": true,
		"reason": "player_view_switched",
		"connection_id": connection_id,
		"world_space_id": destination_world_space_id,
		"cell": destination_cell,
	}

func _try_open_connection_context_menu(screen_position: Vector2) -> bool:
	var result: Dictionary = request_connection_context_at_world_position(_screen_to_world(screen_position), screen_position)
	_debug_right_click_context("connection_context", screen_position, result)
	return bool(result.get("ok", false))

func _try_open_mining_context_menu(screen_position: Vector2) -> bool:
	var result: Dictionary = request_mining_context_at_world_position(_screen_to_world(screen_position), screen_position)
	_debug_right_click_context("mining_context", screen_position, result)
	return bool(result.get("ok", false))

func _debug_right_click_context(stage: String, screen_position: Vector2, result: Dictionary) -> void:
	if not DEBUG_RIGHT_CLICK_CONTEXT:
		return
	var world_position: Vector2 = _screen_to_world(screen_position)
	var active_world_space_id: String = _chunk_manager.get_active_world_space_id()
	var flat_cell: Vector2i = _chunk_manager.world_to_cell(world_position)
	print("[RIGHT_CLICK_CONTEXT] stage=%s mode=%s active_world_space=%s screen=%s world=%s flat_cell=%s hovered_ui=%s result=%s candidates=%s" % [
		stage,
		get_control_mode_name(),
		active_world_space_id,
		screen_position,
		world_position,
		flat_cell,
		get_viewport().gui_get_hovered_control(),
		result,
		_get_right_click_candidate_debug(world_position, active_world_space_id),
	])

func _get_right_click_candidate_debug(world_position: Vector2, world_space_id: String) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for candidate: Vector2i in _chunk_manager.get_visible_terrain_cells_at_world_position(world_position, world_space_id):
		var tile_info: Dictionary = _chunk_manager.get_effective_tile_info(candidate, world_space_id)
		snapshots.append({
			"cell": candidate,
			"terrain": String(tile_info.get("terrain", "")),
			"elevation": int(tile_info.get("elevation", 0)),
			"mineable": bool(tile_info.get("mineable", false)),
			"loaded": _chunk_manager.is_cell_loaded(candidate, world_space_id),
			"world_space_id": world_space_id,
			"dig_validation": _world_state.validate_mining_designation(candidate, world_space_id, true) if _world_state != null else {},
		})
	return snapshots

func _connection_has_endpoint(connection: Dictionary, world_space_id: String, cell: Vector2i) -> bool:
	if String(connection.get("from_world_space_id", "")) == world_space_id and connection.get("from_cell", Vector2i.ZERO) == cell:
		return true
	return bool(connection.get("bidirectional", false)) and String(connection.get("to_world_space_id", "")) == world_space_id and connection.get("to_cell", Vector2i.ZERO) == cell

func _open_context_menu(screen_position: Vector2, actions: Array[Dictionary]) -> void:
	_context_actions = actions.duplicate(true)
	_context_menu.clear()
	for index in range(_context_actions.size()):
		_context_menu.add_item(String(_context_actions[index].get("label", "Action")), index)
	_context_menu.position = Vector2i(roundi(screen_position.x), roundi(screen_position.y))
	_context_menu.popup()

func _on_context_menu_id_pressed(action_id: int) -> void:
	var result: Dictionary = activate_context_menu_action(action_id)
	if not bool(result.get("ok", false)):
		push_warning("Context action failed: %s" % String(result.get("reason", "unknown")))

func _set_selected_colonist(colonist: Colonist) -> void:
	if _selected_colonist != null and is_instance_valid(_selected_colonist):
		_selected_colonist.set_selected(false)
	_selected_colonist = colonist
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		_colonist_info_panel.clear_selection()
		_bottom_ui_controller.close_drawer_if_active(BottomUiController.DRAWER_COLONIST)
		return
	_clear_selected_storage()
	_selected_colonist.set_selected(true)
	_colonist_info_panel.display_colonist(_selected_colonist)
	if not _placement_mode and not _harvest_mode and not _stockpile_mode and not _debug_cliff_mode:
		_bottom_ui_controller.open_drawer(BottomUiController.DRAWER_COLONIST)

func _select_storage_at_cell(cell: Vector2i) -> bool:
	## Selection is transient; storage data remains owned and queried from WorldState.
	var site: Dictionary = _world_state.get_construction_site_at_cell(cell)
	if site.is_empty() or not bool(site.get("completed", false)):
		_clear_selected_storage()
		return false
	var site_id: String = String(site.get("site_id", ""))
	for component: Dictionary in _world_state.get_storage_components():
		if String(component.get("construction_site_id", "")) != site_id:
			continue
		_selected_storage_id = String(component.get("storage_id", ""))
		_refresh_selected_storage_inspector()
		return true
	_clear_selected_storage()
	return false

func _clear_selected_storage() -> void:
	_selected_storage_id = ""
	_storage_inspector_panel.clear_selection()

func _refresh_selected_storage_inspector() -> void:
	if _selected_storage_id.is_empty():
		return
	var component: Dictionary = _world_state.get_storage_component(_selected_storage_id)
	if component.is_empty():
		_clear_selected_storage()
		return
	var definition: Dictionary = BuildingDefinitionRef.get_definition(String(component.get("building_id", "")))
	var building_name: String = String(definition.get("display_name", component.get("building_id", "Storage")))
	_storage_inspector_panel.display_storage(building_name, component)

func _on_colonist_population_replaced() -> void:
	## Saved UI/view selection is intentionally excluded; imports return to the surface presentation.
	_set_selected_colonist(null)
	_clear_selected_storage()
	if _chunk_manager.get_active_world_space_id() != ChunkManager.SURFACE_WORLD_SPACE_ID:
		var surface_actor: Colonist = _colonist_manager.get_first_colonist_in_world_space(ChunkManager.SURFACE_WORLD_SPACE_ID)
		if surface_actor != null:
			_camera.global_position = _chunk_manager.get_cell_world_position(surface_actor.current_cell)
		_chunk_manager.set_active_world_space_id(ChunkManager.SURFACE_WORLD_SPACE_ID)
	_colonist_manager.refresh_active_world_space_visibility()
	call_deferred("ensure_initial_cave_interior")
