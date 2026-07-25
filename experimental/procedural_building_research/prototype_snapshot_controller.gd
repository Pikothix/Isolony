class_name ExperimentalPrototypeSnapshotController
extends Node2D

## Purpose: Coordinate tools and transient cell designation for the snapshot experiment.
## Ownership: Owns active tool, hover, pending paint, drag state, preview orientation, and feedback.
## Integration: Requests all authoritative mutations from ExperimentalPrototypeBuildingService.

const LocationState := preload("res://experimental/procedural_building_research/prototype_location_state.gd")
const BuildingPlan := preload("res://experimental/procedural_building_research/prototype_building_plan.gd")
const BuildingService := preload("res://experimental/procedural_building_research/prototype_building_service.gd")

var location_state: RefCounted
var accepted_plan: RefCounted
var pending_wall_cells: Array[Vector2i] = []
var pending_floor_cells: Array[Vector2i] = []
var hovered_cell := Vector2i(-999, -999)
var tool_mode: StringName = &"inspect"
var opening_orientation_preview: StringName = &""
var _service: RefCounted
var _dragging := false
var _last_drag_screen_position := Vector2.ZERO

@onready var _renderer: Node2D = $SnapshotPanel/PrototypeRenderer
@onready var _wall_button: Button = $Controls/Panel/Margin/VBox/WallButton
@onready var _floor_button: Button = $Controls/Panel/Margin/VBox/FillFloorButton
@onready var _door_button: Button = $Controls/Panel/Margin/VBox/DoorButton
@onready var _window_button: Button = $Controls/Panel/Margin/VBox/WindowButton
@onready var _remove_button: Button = $Controls/Panel/Margin/VBox/RemoveButton
@onready var _confirm_button: Button = $Controls/Panel/Margin/VBox/ConfirmButton
@onready var _cancel_button: Button = $Controls/Panel/Margin/VBox/CancelButton
@onready var _status_label: Label = $Controls/Panel/Margin/VBox/StatusLabel


func _ready() -> void:
	location_state = LocationState.new(Rect2i(0, 0, 12, 10))
	accepted_plan = BuildingPlan.new()
	accepted_plan.clear()
	_service = BuildingService.new()
	_renderer.configure(location_state)
	_renderer.render_plan(accepted_plan)
	_wall_button.pressed.connect(begin_wall_mode)
	_floor_button.pressed.connect(func() -> void: _set_tool(&"fill_floor", "Click inside a closed wall perimeter."))
	_door_button.pressed.connect(func() -> void: _set_tool(&"door", "Click a straight wall cell to place a door."))
	_window_button.pressed.connect(func() -> void: _set_tool(&"window", "Click a straight wall cell to place a window."))
	_remove_button.pressed.connect(func() -> void: _set_tool(&"remove", "Click an opening, wall, or floor cell to remove it."))
	_confirm_button.pressed.connect(confirm_pending_walls)
	_cancel_button.pressed.connect(cancel_pending)
	_set_status("Paint wall cells, confirm them, then fill an enclosed interior.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_pending()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		hovered_cell = _renderer.screen_to_cell(event.position)
		_update_orientation_preview()
		if _dragging:
			_add_drag_path(_last_drag_screen_position, event.position)
			_last_drag_screen_position = event.position
		_renderer.set_preview(pending_wall_cells, hovered_cell)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_pending()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if tool_mode == &"wall":
			_dragging = event.pressed
			if event.pressed:
				_last_drag_screen_position = event.position
				hovered_cell = _renderer.screen_to_cell(event.position)
				_add_pending_wall(hovered_cell)
		elif event.pressed:
			hovered_cell = _renderer.screen_to_cell(event.position)
			apply_tool_at(hovered_cell)


func begin_wall_mode() -> void:
	_set_tool(&"wall", "Paint wall cells, then confirm the pending designation.")


func set_pending_walls_for_validation(cells: Array[Vector2i]) -> void:
	pending_wall_cells = cells.duplicate()
	_renderer.set_preview(pending_wall_cells, hovered_cell)


func confirm_pending_walls() -> Dictionary:
	var result: Dictionary = _service.request_add_wall_cells(accepted_plan, pending_wall_cells, location_state)
	if not result.valid:
		_set_status(result.reason)
		return result
	pending_wall_cells.clear()
	_renderer.set_preview(pending_wall_cells, hovered_cell)
	_renderer.render_plan(accepted_plan)
	tool_mode = &"inspect"
	_set_status("Accepted %d wall cells." % accepted_plan.wall_cells.size())
	return result


func apply_tool_at(cell: Vector2i) -> Dictionary:
	var result: Dictionary
	match tool_mode:
		&"fill_floor": result = _service.request_fill_interior_floors(accepted_plan, cell, location_state)
		&"door": result = _service.request_set_opening(accepted_plan, cell, &"door")
		&"window": result = _service.request_set_opening(accepted_plan, cell, &"window")
		&"remove": result = _remove_at(cell)
		_: return {"valid": false, "reason": "Select a building tool first."}
	if result.valid:
		_renderer.render_plan(accepted_plan)
	_set_status(result.reason)
	_update_orientation_preview()
	return result


func cancel_pending() -> void:
	_dragging = false
	pending_wall_cells.clear()
	pending_floor_cells.clear()
	_renderer.set_preview(pending_wall_cells, hovered_cell)
	_set_status("Pending designation cleared; accepted plan unchanged.")


func _remove_at(cell: Vector2i) -> Dictionary:
	if accepted_plan.openings.has(cell):
		return _service.request_remove_opening(accepted_plan, cell)
	if accepted_plan.wall_cells.has(cell):
		return _service.request_remove_wall_cells(accepted_plan, [cell], location_state)
	if accepted_plan.floor_cells.has(cell):
		return _service.request_remove_floor_cells(accepted_plan, [cell], location_state)
	return {"valid": false, "reason": "There is nothing removable at that cell."}


func _set_tool(mode: StringName, message: String) -> void:
	_dragging = false
	tool_mode = mode
	_update_orientation_preview()
	_set_status(message)


func _add_pending_wall(cell: Vector2i) -> void:
	if location_state.is_buildable(cell) and not pending_wall_cells.has(cell):
		pending_wall_cells.append(cell)
		_renderer.set_preview(pending_wall_cells, hovered_cell)


func _add_drag_path(from_screen: Vector2, to_screen: Vector2) -> void:
	var sample_count := maxi(1, ceili(from_screen.distance_to(to_screen) / 4.0))
	for index in range(1, sample_count + 1):
		_add_pending_wall(_renderer.screen_to_cell(from_screen.lerp(to_screen, float(index) / sample_count)))


func _update_orientation_preview() -> void:
	opening_orientation_preview = &""
	if tool_mode != &"door" and tool_mode != &"window":
		return
	var classified: Dictionary = _service.classify_opening_orientation(accepted_plan.wall_cells, hovered_cell)
	if classified.valid:
		opening_orientation_preview = classified.orientation_group


func _set_status(message: String) -> void:
	_status_label.text = message
