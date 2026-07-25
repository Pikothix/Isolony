extends Node

const GENESIS_SCENE := "res://scenes/Genesis.tscn"
const DESKTOP_SCENE := "res://scenes/Main.tscn"
const DEBUG_SKIP_SETTING := "genesis/debug_skip"


## Startup router only. Desktop and Genesis retain separate ownership and are
## never instantiated together.
func _ready() -> void:
	call_deferred("_route_to_initial_scene")


func _route_to_initial_scene() -> void:
	var next_scene := DESKTOP_SCENE if ProjectSettings.get_setting(DEBUG_SKIP_SETTING, false) else GENESIS_SCENE
	get_tree().change_scene_to_file(next_scene)
