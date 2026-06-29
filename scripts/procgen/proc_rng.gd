extends RefCounted
class_name ProcRng

const UINT32_MASK: int = 0xffffffff
const TREE_SALT: int = 0x4f1bbcdd
const ROCK_SALT: int = 0x27d4eb2f

var _state: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])

static func _u32(value: int) -> int:
	return value & UINT32_MASK

static func _rotl32(value: int, amount: int) -> int:
	var masked: int = _u32(value)
	return _u32((masked << amount) | (masked >> (32 - amount)))

static func _seed_step(state: int) -> Dictionary:
	var current: int = _u32(state + 0x9e3779b9)
	var z: int = current
	z = _u32((z ^ (z >> 16)) * 0x85ebca6b)
	z = _u32((z ^ (z >> 13)) * 0xc2b2ae35)
	z = _u32(z ^ (z >> 16))
	return {"state": current, "value": z}

static func derive_spatial_seed(x: int, y: int, map_seed: int, salt: int) -> int:
	return _u32((x * 73856093) ^ (y * 19349663) ^ map_seed ^ salt)

static func salt_for_kind(kind: String) -> int:
	if kind == "tree":
		return TREE_SALT
	if kind == "rock":
		return ROCK_SALT
	return 0x9e3779b9

static func derive_resource_seed(chunk_coord: Vector2i, local_cell: Vector2i, map_seed: int, kind: String) -> int:
	var kind_salt: int = salt_for_kind(kind)
	var chunk_seed: int = derive_spatial_seed(chunk_coord.x, chunk_coord.y, map_seed, kind_salt ^ 0x51c3d12d)
	return derive_spatial_seed(local_cell.x, local_cell.y, chunk_seed, kind_salt ^ 0xa24baed4)

static func apply_variant_cap(seed: int, variant_cap: int) -> int:
	if variant_cap <= 0:
		return _u32(seed)
	return _u32(seed % variant_cap)

func _init(seed: int) -> void:
	var state: int = _u32(seed)
	for i in range(4):
		var step: Dictionary = _seed_step(state)
		state = step["state"]
		_state[i] = step["value"]
	if (_state[0] | _state[1] | _state[2] | _state[3]) == 0:
		_state[0] = 0x9e3779b9
		_state[1] = 0x243f6a88
		_state[2] = 0xb7e15162
		_state[3] = 0x8aed2a6b

func next_u32() -> int:
	var sum03: int = _u32(_state[0] + _state[3])
	var result: int = _u32(_rotl32(sum03, 7) + _state[0])
	var t: int = _u32(_state[1] << 9)
	_state[2] = _u32(_state[2] ^ _state[0])
	_state[3] = _u32(_state[3] ^ _state[1])
	_state[1] = _u32(_state[1] ^ _state[2])
	_state[0] = _u32(_state[0] ^ _state[3])
	_state[2] = _u32(_state[2] ^ t)
	_state[3] = _rotl32(_state[3], 11)
	return result

func next_float() -> float:
	var hi: int = next_u32() >> 5
	var lo: int = next_u32() >> 6
	var mantissa: float = float(hi) * 67108864.0 + float(lo)
	return mantissa / 9007199254740992.0

func next_range(minimum: float, maximum: float) -> float:
	return minimum + next_float() * (maximum - minimum)

func next_int(minimum: int, maximum: int) -> int:
	var span: int = maximum - minimum + 1
	return mini(int(floor(float(minimum) + next_float() * float(span))), maximum)
