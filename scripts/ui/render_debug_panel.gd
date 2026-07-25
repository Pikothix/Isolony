extends PanelContainer
class_name RenderDebugPanel

## Purpose: Expose transient rendering diagnostics during gameplay.
## Responsibility: Mirror user selections to ChunkManager's presentation setters only.
## Assumption: Number-key debug state and render choices are scene-local and intentionally unsaved.

@export var chunk_manager_path: NodePath = NodePath("../../ChunkManager")

@onready var _shader_enabled: CheckBox = $MarginContainer/VBoxContainer/ShaderEnabled
@onready var _direction_mode: OptionButton = $MarginContainer/VBoxContainer/DirectionRow/DirectionMode
@onready var _debug_elevation: CheckBox = $MarginContainer/VBoxContainer/DebugElevation

var _chunk_manager: ChunkManager


func _ready() -> void:
	_chunk_manager = get_node_or_null(chunk_manager_path) as ChunkManager
	if _chunk_manager == null:
		push_error("RenderDebugPanel requires a valid ChunkManager node path.")
		set_process_unhandled_input(false)
		return
	_direction_mode.add_item("All", ChunkManager.ShaderRimDirectionMode.ALL)
	_direction_mode.add_item("Top Only", ChunkManager.ShaderRimDirectionMode.TOP_ONLY)
	_direction_mode.add_item("Bottom Only", ChunkManager.ShaderRimDirectionMode.BOTTOM_ONLY)
	_direction_mode.add_item("None", ChunkManager.ShaderRimDirectionMode.NONE)
	_shader_enabled.toggled.connect(_on_shader_enabled_toggled)
	_direction_mode.item_selected.connect(_on_direction_mode_selected)
	_debug_elevation.toggled.connect(_on_debug_elevation_toggled)
	_sync_from_chunk_manager()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_3:
		visible = not visible
		if visible:
			_sync_from_chunk_manager()
		get_viewport().set_input_as_handled()


func _sync_from_chunk_manager() -> void:
	_shader_enabled.set_pressed_no_signal(_chunk_manager.is_shader_cliff_rims_enabled())
	_direction_mode.select(_chunk_manager.get_shader_cliff_rim_direction_mode())
	_debug_elevation.set_pressed_no_signal(_chunk_manager.is_shader_cliff_rim_debug_elevation_enabled())
	_update_control_availability()


func _on_shader_enabled_toggled(enabled: bool) -> void:
	_chunk_manager.set_shader_cliff_rims_enabled(enabled)
	_update_control_availability()


func _on_direction_mode_selected(index: int) -> void:
	_chunk_manager.set_shader_cliff_rim_direction_mode(_direction_mode.get_item_id(index))


func _on_debug_elevation_toggled(enabled: bool) -> void:
	_chunk_manager.set_shader_cliff_rim_debug_elevation(enabled)


func _update_control_availability() -> void:
	var shader_enabled := _shader_enabled.button_pressed
	_direction_mode.disabled = not shader_enabled
	_debug_elevation.disabled = not shader_enabled
