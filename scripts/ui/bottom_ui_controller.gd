extends Node
class_name BottomUiController

## Purpose: Own the one transient bottom drawer visible above the persistent toolbar.
## Responsibility: Coordinate UI panel visibility only; simulation state and tool authority remain elsewhere.
## Assumption: Drawer panels are siblings under CanvasLayer and are never saved.

const DRAWER_NONE := "none"
const DRAWER_ARCHITECT := "architect"
const DRAWER_WORK := "work"
const DRAWER_COLONIST := "colonist"

signal active_drawer_changed(drawer_id: String)

@onready var _architect_panel: Control = $"../ArchitectMenu"
@onready var _work_panel: Control = $"../WorkPriorityPanel"
@onready var _colonist_panel: Control = $"../ColonistInfoPanel"

var _active_drawer := DRAWER_NONE

func _ready() -> void:
	_set_drawer_visibility(DRAWER_NONE)

func get_active_drawer() -> String:
	return _active_drawer

func open_drawer(drawer_id: String) -> void:
	if drawer_id != DRAWER_ARCHITECT and drawer_id != DRAWER_WORK and drawer_id != DRAWER_COLONIST:
		close_current_drawer()
		return
	_active_drawer = drawer_id
	_set_drawer_visibility(drawer_id)
	active_drawer_changed.emit(_active_drawer)

func close_current_drawer() -> void:
	if _active_drawer == DRAWER_NONE:
		return
	_active_drawer = DRAWER_NONE
	_set_drawer_visibility(DRAWER_NONE)
	active_drawer_changed.emit(_active_drawer)

func close_drawer_if_active(drawer_id: String) -> void:
	if _active_drawer == drawer_id:
		close_current_drawer()

func _set_drawer_visibility(drawer_id: String) -> void:
	_architect_panel.visible = drawer_id == DRAWER_ARCHITECT
	_work_panel.visible = drawer_id == DRAWER_WORK
	_colonist_panel.visible = drawer_id == DRAWER_COLONIST
