extends PanelContainer
class_name SelectedTilePanel

const TerrainConfigRef = preload("res://scripts/world/terrain_config.gd")

@onready var _preview_rect: TextureRect = $MarginContainer/VBoxContainer/PreviewRect
@onready var _name_label: Label = $MarginContainer/VBoxContainer/NameLabel

var _terrain_layer: TileMapLayer

func setup(terrain_layer: TileMapLayer) -> void:
	_terrain_layer = terrain_layer

func set_selected_tile(entry: Dictionary) -> void:
	var terrain_id: String = String(entry.get("id", ""))
	var display_name: String = String(entry.get("label", TerrainConfigRef.get_display_name(terrain_id)))
	_name_label.text = display_name if not display_name.is_empty() else "Unknown"
	if terrain_id.is_empty():
		_preview_rect.texture = null
		_preview_rect.visible = false
		return
	_preview_rect.texture = _build_preview_texture(terrain_id)
	_preview_rect.visible = _preview_rect.texture != null

func _build_preview_texture(terrain_id: String) -> Texture2D:
	if _terrain_layer == null or _terrain_layer.tile_set == null:
		return null
	var atlas_coords: Vector2i = TerrainConfigRef.get_atlas_coords(terrain_id)
	if atlas_coords == TerrainConfigRef.INVALID_ATLAS_COORDS:
		return null
	var source: TileSetSource = _terrain_layer.tile_set.get_source(TerrainConfigRef.TILE_SOURCE_ID)
	if source == null or not source is TileSetAtlasSource:
		return null
	var atlas_source: TileSetAtlasSource = source as TileSetAtlasSource
	var atlas_texture: AtlasTexture = AtlasTexture.new()
	atlas_texture.atlas = atlas_source.texture
	atlas_texture.region = Rect2(atlas_coords * atlas_source.texture_region_size, atlas_source.texture_region_size)
	return atlas_texture
