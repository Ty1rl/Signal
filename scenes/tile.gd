class_name Tile
extends Area2D

signal clicked(tile_coord: Vector2i)

enum Terrain { PLAIN, FOREST, WALL }
enum TowerRole { NONE, NORMAL, SOURCE, TARGET }
enum State {
	REACHABLE,
	BROADCASTING,
	SELECTED,
}

@export var plain_region: Rect2 = Rect2(0, 0, 32, 64)
@export var wall_region: Rect2 = Rect2(32, 0, 32, 64)
@export var forest_region: Rect2 = Rect2(64, 0, 32, 64)
@export var tower_off_plain_region: Rect2 = Rect2(96, 0, 32, 64)
@export var tower_off_wall_region: Rect2 = Rect2(128, 0, 32, 64)
@export var tower_off_forest_region: Rect2 = Rect2(160, 0, 32, 64)
@export var tower_on_plain_region: Rect2 = Rect2(192, 0, 32, 64)
@export var tower_on_wall_region: Rect2 = Rect2(224, 0, 32, 64)
@export var tower_on_forest_region: Rect2 = Rect2(256, 0, 32, 64)

@onready var terrain_sprite: Sprite2D = $TerrainSprite
@onready var highlights: Array[Sprite2D] = [$Highlight0, $Highlight1, $Highlight2]
@onready var collision: CollisionShape2D = $CollisionShape2D

var tile_coord: Vector2i = Vector2i.ZERO
var terrain: int = Terrain.PLAIN
var tower_role: int = TowerRole.NONE
var tower_shape: String = ""
var highlight_colors: Array = [Color(0.3, 0.8, 1.0, 0.4)]
var _states: Dictionary = {}

func _ready() -> void:
	_refresh_visual()

# --- Structural setters ---
func set_terrain(t: int) -> void:
	terrain = t
	_refresh_visual()

func set_tower_role(r: int) -> void:
	tower_role = r
	_refresh_visual()

func set_tower_shape(s: String) -> void:
	tower_shape = s
	_refresh_visual()

func set_highlight_colors(colors: Array) -> void:
	highlight_colors = colors
	_refresh_visual()

# --- Transient state ---
func add_state(s: int) -> void:
	_states[s] = true
	_refresh_visual()

func remove_state(s: int) -> void:
	_states.erase(s)
	_refresh_visual()

func has_state(s: int) -> bool:
	return _states.has(s)

func clear_transient_states() -> void:
	_states.clear()
	_refresh_visual()

# --- Visual refresh ---
func _refresh_visual() -> void:
	_update_terrain_sprite()
	_update_highlight()

func _update_terrain_sprite() -> void:
	var region: Rect2 = _pick_region()
	if terrain_sprite.texture is AtlasTexture:
		terrain_sprite.texture.region = region
	terrain_sprite.modulate = _compute_tint()

func _pick_region() -> Rect2:
	var has_tower: bool = tower_role != TowerRole.NONE
	var broadcasting: bool = has_state(State.BROADCASTING)
	
	if not has_tower:
		match terrain:
			Terrain.FOREST: return forest_region
			Terrain.WALL:   return wall_region
			_:               return plain_region
	
	if broadcasting:
		match terrain:
			Terrain.FOREST: return tower_on_forest_region
			Terrain.WALL:   return tower_on_wall_region
			_:               return tower_on_plain_region
	
	# Tower off (controlled, uncontrolled, source, target — the "state" differences show via modulate)
	match terrain:
		Terrain.FOREST: return tower_off_forest_region
		Terrain.WALL:   return tower_off_wall_region
		_:               return tower_off_plain_region

func _compute_tint() -> Color:
	if tower_role == TowerRole.NONE:
		return Color.WHITE
	
	if has_state(State.SELECTED):
		return Color(1.8, 1.8, 0.6)
	if tower_role == TowerRole.TARGET and not has_state(State.REACHABLE):
		return Color(0.5, 0.2, 0.5)
	if not has_state(State.REACHABLE):
		return Color(0.4, 0.4, 0.4)
	if has_state(State.BROADCASTING):
		match tower_shape:
			"Wide":  return Color(0.6, 1.8, 0.8)
			"Pulse": return Color(0.6, 1.0, 1.8)
			"Skip":  return Color(1.8, 1.0, 0.4)
			_:        return Color(0.7, 1.5, 1.8)
	if tower_role == TowerRole.SOURCE:
		return Color(0.6, 1.8, 0.6)
	if tower_role == TowerRole.TARGET:
		return Color(1.8, 0.6, 1.8)
	return Color.WHITE

func _update_highlight() -> void:
	var active: bool = has_state(State.REACHABLE) and tower_role == TowerRole.NONE
	for i in highlights.size():
		if active and i < highlight_colors.size():
			highlights[i].visible = true
			highlights[i].modulate = highlight_colors[i]
		else:
			highlights[i].visible = false
