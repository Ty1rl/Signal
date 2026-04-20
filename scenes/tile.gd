class_name Tile
extends Area2D

#signal clicked(tile_coord: Vector2i)

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

# Terrain + tower collision polygons. Any may be null if partner hasn't drawn it yet.
@onready var _col_plain: CollisionPolygon2D = get_node_or_null("CollisionPlain")
@onready var _col_wall: CollisionPolygon2D = get_node_or_null("CollisionWall")
@onready var _col_forest: CollisionPolygon2D = get_node_or_null("CollisionForest")
@onready var _col_tower_off: CollisionPolygon2D = get_node_or_null("CollisionTowerOff")
@onready var _col_tower_on: CollisionPolygon2D = get_node_or_null("CollisionTowerOn")

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
	_update_collision()

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
	
	match terrain:
		Terrain.FOREST: return tower_off_forest_region
		Terrain.WALL:   return tower_off_wall_region
		_:               return tower_off_plain_region

func _compute_tint() -> Color:
	if tower_role == TowerRole.NONE:
		# Terrain tint
		match terrain:
			Terrain.FOREST: return Color(0.75, 0.95, 0.80)  # soft green
			Terrain.WALL:   return Color(0.70, 0.75, 0.85)  # cool slate
			_:               return Color(0.95, 0.97, 1.00)  # pale white-blue
	
	# Tower states
	if has_state(State.SELECTED):
		return Color(1.8, 1.8, 0.6)
	if tower_role == TowerRole.TARGET and not has_state(State.REACHABLE):
		return Color(0.5, 0.2, 0.5)
	if not has_state(State.REACHABLE):
		# OFF tower: warm amber so it distinguishes from dark terrain
		return Color(0.85, 0.70, 0.40)
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

# --- Collision ---
# Enables one terrain polygon + optionally one tower polygon based on state.
func _update_collision() -> void:
	# Terrain layer
	_set_poly_enabled(_col_plain, terrain == Terrain.PLAIN)
	_set_poly_enabled(_col_wall, terrain == Terrain.WALL)
	_set_poly_enabled(_col_forest, terrain == Terrain.FOREST)
	
	# Tower layer
	var has_tower: bool = tower_role != TowerRole.NONE
	var broadcasting: bool = has_state(State.BROADCASTING)
	_set_poly_enabled(_col_tower_off, has_tower and not broadcasting)
	_set_poly_enabled(_col_tower_on, has_tower and broadcasting)

func _set_poly_enabled(poly: CollisionPolygon2D, should_enable: bool) -> void:
	if poly == null:
		return
	poly.disabled = not should_enable

# Returns list of currently-active CollisionPolygon2Ds (terrain + optionally tower)
func active_collisions() -> Array:
	var result: Array = []
	for p in [_col_plain, _col_wall, _col_forest, _col_tower_off, _col_tower_on]:
		if p != null and not p.disabled:
			result.append(p)
	return result
