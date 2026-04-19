class_name Tile
extends Area2D

signal clicked(tile_coord: Vector2i)

enum Terrain { PLAIN, FOREST, WALL }
enum TowerRole { NONE, NORMAL, SOURCE, TARGET }
enum State {
	REACHABLE,      # tile is in controlled_tiles (signal reaches here)
	BROADCASTING,   # a transmitter on this tile is actively firing
	SELECTED,       # player has selected this tower
}

@export var plain_region: Rect2 = Rect2(0, 0, 32, 64)
@export var wall_region: Rect2 = Rect2(32, 0, 32, 64)
@export var forest_region: Rect2 = Rect2(64, 0, 32, 64)
@export var tower_plain_region: Rect2 = Rect2(96, 0, 32, 64)
@export var tower_wall_region: Rect2 = Rect2(128, 0, 32, 64)
@export var tower_forest_region: Rect2 = Rect2(160, 0, 32, 64)

@onready var terrain_sprite: Sprite2D = $TerrainSprite
@onready var tower_base: Sprite2D = $TowerBase
@onready var tower_mid: Sprite2D = $TowerMid
@onready var tower_top: Sprite2D = $TowerTop
@onready var highlight: Sprite2D = $Highlight
@onready var collision: CollisionShape2D = $CollisionShape2D
var highlight_color: Color = Color(0.3, 0.8, 1.0, 0.4)
var tile_coord: Vector2i = Vector2i.ZERO
var terrain: int = Terrain.PLAIN
var tower_role: int = TowerRole.NONE
var _states: Dictionary = {}
var controlled_tile_shape: Dictionary = {}   # Vector2i -> shape_name (first shape to reach)

@onready var highlights: Array[Sprite2D] = [$Highlight0, $Highlight1, $Highlight2]

var highlight_colors: Array = [Color(0.3, 0.8, 1.0, 0.4)]

func set_highlight_colors(colors: Array) -> void:
	highlight_colors = colors
	_refresh_visual()

func _update_highlight() -> void:
	var active := has_state(State.REACHABLE) and tower_role == TowerRole.NONE
	for i in highlights.size():
		if active and i < highlight_colors.size():
			highlights[i].visible = true
			highlights[i].modulate = highlight_colors[i]
		else:
			highlights[i].visible = false

var tower_shape: String = ""

func set_tower_shape(s: String) -> void:
	tower_shape = s
	_refresh_visual()

func _ready() -> void:
	# input_event.connect(_on_input_event)
	_refresh_visual()

# --- Structural setters ---
func set_terrain(t: int) -> void:
	terrain = t
	_refresh_visual()

func set_tower_role(r: int) -> void:
	tower_role = r
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
	_update_tower_sprites()
	_update_highlight()
	_update_clickable()

func _update_terrain_sprite() -> void:
	var region: Rect2 = plain_region
	var has_tower: bool = tower_role != TowerRole.NONE
	
	if has_tower:
		match terrain:
			Terrain.FOREST: region = tower_forest_region
			Terrain.WALL:   region = tower_wall_region
			_:               region = tower_plain_region
	else:
		match terrain:
			Terrain.FOREST: region = forest_region
			Terrain.WALL:   region = wall_region
			_:               region = plain_region
	
	if terrain_sprite.texture is AtlasTexture:
		terrain_sprite.texture.region = region

func _update_tower_sprites() -> void:
	var has_tower: bool = tower_role != TowerRole.NONE
	tower_base.visible = false
	tower_mid.visible = false
	tower_top.visible = false
	
	if not has_tower:
		terrain_sprite.modulate = Color.WHITE
		return
	
	var tint: Color = Color.WHITE
	if has_state(State.SELECTED):
		tint = Color(1.8, 1.8, 0.6)
	elif tower_role == TowerRole.TARGET and not has_state(State.REACHABLE):
		tint = Color(0.5, 0.2, 0.5)
	elif not has_state(State.REACHABLE):
		tint = Color(0.4, 0.4, 0.4)
	elif has_state(State.BROADCASTING):
		match tower_shape:
			"Wide":  tint = Color(0.6, 1.8, 0.8)
			"Pulse": tint = Color(0.6, 1.0, 1.8)
			"Skip":  tint = Color(1.8, 1.0, 0.4)
			_:        tint = Color(0.7, 1.5, 1.8)
	elif tower_role == TowerRole.SOURCE:
		tint = Color(0.6, 1.8, 0.6)
	elif tower_role == TowerRole.TARGET:
		tint = Color(1.8, 0.6, 1.8)
	
	terrain_sprite.modulate = tint

#func _update_tower_sprites() -> void:
	#var has_tower: bool = tower_role != TowerRole.NONE
	#tower_base.visible = has_tower
	#tower_mid.visible = has_tower
	#tower_top.visible = has_tower
	#if not has_tower:
		#return
	#
	#var tint: Color = Color.WHITE
	#if has_state(State.SELECTED):
		#tint = Color(1.8, 1.8, 0.6)
	#elif tower_role == TowerRole.TARGET and not has_state(State.REACHABLE):
		#tint = Color(0.5, 0.2, 0.5)  # dark magenta — unreached target
	#elif not has_state(State.REACHABLE):
		#tint = Color(0.4, 0.4, 0.4)  # generic uncontrolled
	#elif has_state(State.BROADCASTING):
		#if tower_shape != "":
			#tint = Color(1.5, 1.5, 1.5)  # fallback
			## Match shape color but more saturated/brighter for the tower
			#match tower_shape:
				#"Wide":  tint = Color(0.6, 1.8, 0.8)
				#"Pulse": tint = Color(0.6, 1.0, 1.8)
				#"Skip":  tint = Color(1.8, 1.0, 0.4)
		#else:
			#tint = Color(0.7, 1.5, 1.8)
	#elif tower_role == TowerRole.SOURCE:
		#tint = Color(0.6, 1.8, 0.6)
	#elif tower_role == TowerRole.TARGET:
		#tint = Color(1.8, 0.6, 1.8)
	#
	#tower_base.modulate = tint
	#tower_mid.modulate = tint
	#tower_top.modulate = tint



func _update_clickable() -> void:
	input_pickable = tower_role != TowerRole.NONE and has_state(State.REACHABLE)
	# print("input_pickable=", input_pickable, " shape_pos=", collision.position, " shape_size=")

# func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
#	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
#		print("Tile clicked: ", tile_coord, " priority=", priority, " z_index=", z_index)
#		clicked.emit(tile_coord)
#		get_viewport().set_input_as_handled()
