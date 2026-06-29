extends Camera2D
class_name CameraController

@export var pan_speed: float = 220.0
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0
@export var max_zoom: float = 2.0

func _process(delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	position += input_vector * pan_speed * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(zoom_step)

func _apply_zoom(step: float) -> void:
	var next_zoom: float = clampf(zoom.x + step, min_zoom, max_zoom)
	zoom = Vector2.ONE * next_zoom
