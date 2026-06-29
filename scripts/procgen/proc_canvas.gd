extends RefCounted
class_name ProcCanvas

var width: int
var height: int
var data: PackedByteArray

func _init(canvas_width: int, canvas_height: int) -> void:
	width = canvas_width
	height = canvas_height
	data = PackedByteArray()
	data.resize(width * height * 4)

func get_index(x: int, y: int) -> int:
	return (y * width + x) * 4

func set_pixel(x: int, y: int, r: int, g: int, b: int, a: int) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var i: int = get_index(x, y)
	data[i] = r
	data[i + 1] = g
	data[i + 2] = b
	data[i + 3] = a

func get_alpha(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	return data[get_index(x, y) + 3]

func to_image() -> Image:
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
