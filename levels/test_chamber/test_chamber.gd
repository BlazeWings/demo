extends Node2D

## Test chamber: procedurally builds terrain + entities from the ASCII map below.
##
## Contract: memory/api-contract-v1.md §10.4 (terrain is generated at runtime, no TileSet)
## and §11.4 (markers instantiate entity scenes with load(), then camera limits are pushed).
##
## Map legend:
##   #  solid terrain      (terrain_purple, one Sprite2D per cell, merged StaticBody2D per run)
##   =  one-way platform   (platform_red_wide, one_way_collision, jump-through from below)
##   ^  spikes             (props/spikes.tscn, one instance per contiguous run, sits on the ground)
##   C  checkpoint         (props/checkpoint/checkpoint.tscn)
##   P  player spawn       (entities/player/knight.tscn)
##   K  skeleton           (entities/enemies/skeleton/skeleton.tscn)
##   A  archer             (entities/enemies/archer/archer.tscn)
##   .  empty
##
## World size: 56 columns x 18 rows x 32 px = 1792 x 576 px.

const CELL_SIZE: int = 32
const MAP_ROWS: int = 18
const MAP_COLUMNS: int = 56
const TERRAIN_SCALE: float = 2.0
## Visual/collision thickness of a one-way platform cell (platform_red_wide is 38x8 -> 76x16).
const PLATFORM_THICKNESS: int = 16
## Physics layer 3 "terrain" = bit value 4 (§1).
const TERRAIN_COLLISION_LAYER: int = 4
const HAZARD_COLLISION_LAYER: int = 8
const PLAYER_COLLISION_LAYER: int = 1

const TERRAIN_TEXTURE_PATH: String = "res://assets/sprites/tiles/terrain_purple.png"
const PLATFORM_TEXTURE_PATH: String = "res://assets/sprites/tiles/platform_red_wide.png"
const KILL_ZONE_SCRIPT_PATH: String = "res://props/kill_zone.gd"

const SOLID_MARKER: String = "#"
const PLATFORM_MARKER: String = "="
const SPIKES_MARKER: String = "^"
const PLAYER_MARKER: String = "P"

const MARKER_SCENES: Dictionary = {
	"P": "res://entities/player/knight.tscn",
	"K": "res://entities/enemies/skeleton/skeleton.tscn",
	"A": "res://entities/enemies/archer/archer.tscn",
	"^": "res://props/spikes/spikes.tscn",
	"C": "res://props/checkpoint/checkpoint.tscn",
}

const MARKER_NAMES: Dictionary = {
	"P": "Player",
	"K": "Skeleton",
	"A": "Archer",
	"^": "Spikes",
	"C": "Checkpoint",
}

## 56 columns x 18 rows. Row 0-8 are sky, row 17 the bottom.
## Floor surface = top of row 14 (y = 448). Spike pit cols 16-19 (2 cells deep, escapable).
## Gash cols 32-35 (128 px wide, bottomless -> KillZone). Upper ledge = row 10 (y = 320),
## reached from the one-way platform at row 12 cols 40-43 (64 px steps, jump height ~94 px).
const MAP: Array[String] = [
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#......................................................#",
	"#................................................A.....#",
	"#...........................................############",
	"#..........................A.........................###",
	"#.......====............====............====.........###",
	"#..P...C....K...............K.........C.....K..........#",
	"################....############....####################",
	"################^^^^############....####################",
	"################################....####################",
	"################################....####################",
]

const KILL_ZONE_HEIGHT: float = 192.0

## Map metrics, derived in _ready (also used by the level assembly for the KillZone bounds).
var map_rows: int = MAP_ROWS
var map_columns: int = MAP_COLUMNS
var map_pixel_size: Vector2 = Vector2(MAP_COLUMNS * CELL_SIZE, MAP_ROWS * CELL_SIZE)
## Where the player was spawned; becomes the initial respawn point.
var player_spawn: Vector2 = Vector2.ZERO

var _terrain_root: Node2D


func _ready() -> void:
	_read_map_metrics()
	_build_terrain()
	_spawn_markers()
	_ensure_kill_zone()
	_setup_camera_limits()
	if player_spawn != Vector2.ZERO:
		GameManager.set_respawn(player_spawn)
	else:
		push_warning("[test_chamber] no '%s' marker in the map, respawn point not set" % PLAYER_MARKER)


## World-space bounds of the level, in pixels.
func get_map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, map_pixel_size)


func _read_map_metrics() -> void:
	map_rows = MAP.size()
	map_columns = 0
	for row in map_rows:
		map_columns = maxi(map_columns, MAP[row].length())
		if MAP[row].length() != MAP_COLUMNS:
			push_warning("[test_chamber] map row %d is %d chars, expected %d" % [row, MAP[row].length(), MAP_COLUMNS])
	map_pixel_size = Vector2(map_columns * CELL_SIZE, map_rows * CELL_SIZE)


func _cell(column: int, row: int) -> String:
	if row < 0 or row >= map_rows or column < 0 or column >= map_columns:
		return "."
	return MAP[row][column]


func _cell_center(column: int, row: int) -> Vector2:
	return Vector2((float(column) + 0.5) * CELL_SIZE, (float(row) + 0.5) * CELL_SIZE)


# --- terrain -------------------------------------------------------------------

func _build_terrain() -> void:
	var terrain_texture := load(TERRAIN_TEXTURE_PATH) as Texture2D
	var platform_texture := load(PLATFORM_TEXTURE_PATH) as Texture2D
	if terrain_texture == null:
		push_warning("[test_chamber] missing terrain texture: %s" % TERRAIN_TEXTURE_PATH)
	if platform_texture == null:
		push_warning("[test_chamber] missing platform texture: %s" % PLATFORM_TEXTURE_PATH)
	_terrain_root = Node2D.new()
	_terrain_root.name = "Terrain"
	add_child(_terrain_root)
	for row in map_rows:
		var column := 0
		while column < map_columns:
			var marker := _cell(column, row)
			if marker != SOLID_MARKER and marker != PLATFORM_MARKER:
				column += 1
				continue
			var run_start := column
			while column < map_columns and _cell(column, row) == marker:
				column += 1
			var run_length := column - run_start
			for cell_column in range(run_start, run_start + run_length):
				_add_cell_sprite(marker, cell_column, row, terrain_texture, platform_texture)
			_add_run_collision(marker, run_start, run_length, row)


func _add_cell_sprite(marker: String, column: int, row: int, terrain_texture: Texture2D, platform_texture: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Tile_%d_%d" % [row, column]
	if marker == PLATFORM_MARKER:
		sprite.texture = platform_texture
		sprite.scale = Vector2(TERRAIN_SCALE, TERRAIN_SCALE)
		sprite.centered = false
		sprite.position = Vector2(column * CELL_SIZE, row * CELL_SIZE)
	else:
		sprite.texture = terrain_texture
		sprite.scale = Vector2(TERRAIN_SCALE, TERRAIN_SCALE)
		sprite.position = _cell_center(column, row)
	_terrain_root.add_child(sprite)


## One StaticBody2D + one rectangle per contiguous horizontal run of the same marker.
func _add_run_collision(marker: String, run_start: int, run_length: int, row: int) -> void:
	var body := StaticBody2D.new()
	body.name = "Solid_%d_%d" % [row, run_start] if marker == SOLID_MARKER else "Platform_%d_%d" % [row, run_start]
	body.collision_layer = TERRAIN_COLLISION_LAYER
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	var run_width := float(run_length * CELL_SIZE)
	if marker == PLATFORM_MARKER:
		rectangle.size = Vector2(run_width, float(PLATFORM_THICKNESS))
		shape_node.position = Vector2(float(run_start * CELL_SIZE) + run_width * 0.5, float(row * CELL_SIZE) + float(PLATFORM_THICKNESS) * 0.5)
		shape_node.one_way_collision = true
	else:
		rectangle.size = Vector2(run_width, float(CELL_SIZE))
		shape_node.position = Vector2(float(run_start * CELL_SIZE) + run_width * 0.5, float(row * CELL_SIZE) + float(CELL_SIZE) * 0.5)
	shape_node.shape = rectangle
	body.add_child(shape_node)
	_terrain_root.add_child(body)


# --- markers -------------------------------------------------------------------

func _spawn_markers() -> void:
	for row in map_rows:
		var column := 0
		while column < map_columns:
			var marker := _cell(column, row)
			if not MARKER_SCENES.has(marker):
				column += 1
				continue
			var run_length := 1
			if marker == SPIKES_MARKER:
				while column + run_length < map_columns and _cell(column + run_length, row) == marker:
					run_length += 1
			# One instance per run, centred on it (spike art is much wider than one cell).
			_spawn_marker(marker, column, row, (float(column) + float(run_length) * 0.5) * float(CELL_SIZE))
			column += run_length


func _spawn_marker(marker: String, column: int, row: int, center_x: float) -> void:
	var path: String = MARKER_SCENES[marker]
	if not ResourceLoader.exists(path):
		push_warning("[test_chamber] marker '%s' (col %d, row %d): scene not available yet: %s" % [marker, column, row, path])
		return
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("[test_chamber] marker '%s': could not load %s" % [marker, path])
		return
	var instance := scene.instantiate()
	if not (instance is Node2D):
		push_warning("[test_chamber] marker '%s': %s root is not a Node2D" % [marker, path])
		instance.free()
		return
	var node := instance as Node2D
	# The marker cell sits on the cell below it; align the entity's lowest extent to that surface.
	var ground_y := float((row + 1) * CELL_SIZE)
	node.position = Vector2(center_x, ground_y - _bottom_offset(node))
	node.name = "%s_%d_%d" % [MARKER_NAMES[marker], row, column]
	add_child(node)
	if marker == PLAYER_MARKER:
		player_spawn = node.position


## Distance from the entity origin down to its lowest point, in this level's coordinates.
## Prefers the body's own collider (characters), then any collider, then sprite bounds.
func _bottom_offset(node: Node2D) -> float:
	var direct := _direct_collider(node)
	if direct != null:
		return _point_offset(node, direct)
	var acc: Array = [-INF, -INF]
	for child in node.get_children():
		_scan_extents(child, _origin_transform(node), acc)
	var collider_bottom: float = acc[0]
	var visual_bottom: float = acc[1]
	if collider_bottom != -INF:
		return collider_bottom
	if visual_bottom != -INF:
		return visual_bottom
	return 0.0


func _direct_collider(node: Node2D) -> CollisionShape2D:
	for child in node.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


func _point_offset(node: Node2D, collider: CollisionShape2D) -> float:
	var height := _shape_height(collider.shape)
	if height <= 0.0:
		return 0.0
	return (node.transform * collider.transform * Vector2(0.0, height * 0.5)).y


func _origin_transform(node: Node2D) -> Transform2D:
	var transform := node.transform
	transform.origin = Vector2.ZERO
	return transform


func _scan_extents(node: Node, transform: Transform2D, acc: Array) -> void:
	var local := transform
	if node is Node2D:
		local = transform * (node as Node2D).transform
	if node is CollisionShape2D:
		var height := _shape_height((node as CollisionShape2D).shape)
		if height > 0.0:
			acc[0] = maxf(acc[0], (local * Vector2(0.0, height * 0.5)).y)
	if node is Sprite2D:
		var rect := (node as Sprite2D).get_rect()
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
			acc[1] = maxf(acc[1], (local * corner).y)
	for child in node.get_children():
		_scan_extents(child, local, acc)


func _shape_height(shape: Shape2D) -> float:
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y
	if shape is CapsuleShape2D:
		return (shape as CapsuleShape2D).height
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius * 2.0
	return 0.0


# --- plumbing ------------------------------------------------------------------

## Fallback for the KillZone the level scene is supposed to carry (§11.4):
## without it, falling through the gash would never reset the player.
func _ensure_kill_zone() -> void:
	if _has_kill_zone():
		return
	if not ResourceLoader.exists(KILL_ZONE_SCRIPT_PATH):
		push_warning("[test_chamber] no KillZone in the level scene and %s does not exist yet" % KILL_ZONE_SCRIPT_PATH)
		return
	var script := load(KILL_ZONE_SCRIPT_PATH) as GDScript
	if script == null:
		return
	var instance: Object = script.new()
	if not (instance is Area2D):
		if instance is Node:
			(instance as Node).free()
		return
	var area := instance as Area2D
	area.name = "KillZone"
	area.collision_layer = HAZARD_COLLISION_LAYER
	area.collision_mask = PLAYER_COLLISION_LAYER
	area.monitoring = true
	var shape_node := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(map_pixel_size.x, KILL_ZONE_HEIGHT)
	shape_node.shape = rectangle
	area.add_child(shape_node)
	area.position = Vector2(map_pixel_size.x * 0.5, map_pixel_size.y + KILL_ZONE_HEIGHT * 0.5)
	add_child(area)


func _has_kill_zone() -> bool:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Variant = node.get_script()
		if script is Script and (script as Script).resource_path == KILL_ZONE_SCRIPT_PATH:
			return true
		for child in node.get_children():
			stack.append(child)
	return false


func _setup_camera_limits() -> void:
	get_tree().call_group("game_camera", "set_limits", 0, 0, int(map_pixel_size.x), int(map_pixel_size.y))
