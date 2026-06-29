extends RefCounted
class_name ProcSpriteCache

const ProcBoulders = preload("res://scripts/procgen/proc_boulders.gd")
const ProcRng = preload("res://scripts/procgen/proc_rng.gd")
const ProcTrees = preload("res://scripts/procgen/proc_trees.gd")

static var _texture_cache: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0
static var _debug_logging: bool = false

static func clear() -> void:
	_texture_cache.clear()
	_cache_hits = 0
	_cache_misses = 0

static func set_debug_logging(enabled: bool) -> void:
	_debug_logging = enabled

static func get_cache_size() -> int:
	return _texture_cache.size()

static func get_stats() -> Dictionary:
	return {"cache_hits": _cache_hits, "cache_misses": _cache_misses, "unique_textures": _texture_cache.size()}

static func prewarm(kind: String, variant_cap: int, archetypes: PackedStringArray, terrain_tags: PackedStringArray, size_tiers: PackedStringArray, size_map: Dictionary) -> void:
	if variant_cap <= 0:
		return
	for terrain_tag: String in terrain_tags:
		for size_tier: String in size_tiers:
			var size: int = int(size_map.get(size_tier, 20))
			for archetype: String in archetypes:
				for variant_id in range(variant_cap):
					get_texture(kind, variant_id, size, variant_cap, archetype, terrain_tag, size_tier)
	if _debug_logging:
		print("ProcSpriteCache prewarm kind=", kind, " total_unique=", _texture_cache.size())

static func get_texture(kind: String, seed: int, size: int, variant_cap: int = 0, archetype: String = "", terrain_tag: String = "", size_tier: String = "medium") -> Texture2D:
	var effective_seed: int = ProcRng.apply_variant_cap(seed, variant_cap)
	var key: String = "%s:%s:%s:%s:%d:%d" % [kind, archetype, terrain_tag, size_tier, effective_seed, size]
	if _texture_cache.has(key):
		_cache_hits += 1
		return _texture_cache[key]
	_cache_misses += 1
	var result: Dictionary = {}
	if kind == "tree":
		result = ProcTrees.generate_tree(effective_seed, size, archetype, terrain_tag, size_tier)
	elif kind == "rock":
		result = ProcBoulders.generate_boulder(effective_seed, size, archetype, terrain_tag, size_tier)
	else:
		return null
	var image: Image = result["canvas"].to_image()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	if _debug_logging:
		print("ProcSpriteCache miss kind=", kind, " archetype=", archetype, " terrain=", terrain_tag, " tier=", size_tier, " variant=", effective_seed, " unique=", _texture_cache.size())
	return texture
