extends CanvasLayer

## HUD: heart row (health) + soul counter.
##
## Contract: memory/api-contract-v1.md §6 and §10.3.
## Scene tree expected from the level assembly (all optional — missing pieces are built here):
##   HUD (CanvasLayer, this script)
##   ├── Hearts (HBoxContainer)
##   └── Soul (Node)
##       ├── CoinIcon (TextureRect)
##       └── SoulLabel (Label)
##
## There is no heart_empty.png (§10.3): empty hearts are heart_full.png with a dark modulate.
## The player is spawned at runtime by the level, so binding is retried until it succeeds.

const HEART_TEXTURE_PATH: String = "res://assets/sprites/ui/heart_full.png"
const COIN_TEXTURE_PATH: String = "res://assets/sprites/ui/coin.png"
## heart_full.png is 70x63; drawn at half size to fit the 640x360 viewport.
const HEART_DISPLAY_SIZE: Vector2 = Vector2(35.0, 32.0)
const COIN_DISPLAY_SIZE: Vector2 = Vector2(22.0, 23.0)
const HEART_DIM_COLOR: Color = Color(0.25, 0.25, 0.25, 1.0)
const HEART_SEPARATION: int = 2
const HEARTS_ORIGIN: Vector2 = Vector2(8.0, 4.0)
const SOUL_ORIGIN: Vector2 = Vector2(10.0, 40.0)
const SOUL_LABEL_OFFSET: Vector2 = Vector2(26.0, 2.0)
const FALLBACK_MAX_HEALTH: int = 5
const PLAYER_RETRY_INTERVAL: float = 0.25
const LABEL_FONT_SIZE: int = 16

var _hearts_box: HBoxContainer
var _coin_icon: TextureRect
var _soul_label: Label
var _hearts: Array[TextureRect] = []
var _health: Node
var _retry_timer: float = 0.0


func _ready() -> void:
	_hearts_box = get_node_or_null("Hearts") as HBoxContainer
	_coin_icon = get_node_or_null("Soul/CoinIcon") as TextureRect
	_soul_label = get_node_or_null("Soul/SoulLabel") as Label
	_build_missing_nodes()
	if not GameManager.soul_changed.is_connected(_on_soul_changed):
		GameManager.soul_changed.connect(_on_soul_changed)
	_on_soul_changed(GameManager.soul)
	_apply_health(FALLBACK_MAX_HEALTH, FALLBACK_MAX_HEALTH)
	call_deferred("_bind_player")


func _process(delta: float) -> void:
	if _health != null and is_instance_valid(_health):
		return
	_retry_timer -= delta
	if _retry_timer <= 0.0:
		_retry_timer = PLAYER_RETRY_INTERVAL
		_bind_player()


func _bind_player() -> void:
	if _health != null and is_instance_valid(_health):
		return
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health := _find_health_component(player)
	if health == null:
		return
	_health = health
	_health.health_changed.connect(_on_health_changed)
	var current := FALLBACK_MAX_HEALTH
	if _health.has_method("get_health"):
		current = int(_health.get_health())
	var maximum := current
	var declared: Variant = _health.get("max_health")
	if declared is int or declared is float:
		maximum = int(declared)
	_apply_health(current, maximum)
	set_process(false)   # 信号已绑定，停止重试轮询


## Depth-first search for a node exposing the HealthComponent signal/API (§3).
func _find_health_component(node: Node) -> Node:
	if node.has_signal("health_changed") and node.has_method("get_health"):
		return node
	for child in node.get_children():
		var found := _find_health_component(child)
		if found != null:
			return found
	return null


func _on_health_changed(current: int, maximum: int) -> void:
	_apply_health(current, maximum)


func _on_soul_changed(value: int) -> void:
	if _soul_label == null:
		return
	_soul_label.text = str(value)


func _apply_health(current: int, maximum: int) -> void:
	_build_hearts(maxi(maximum, 1))
	for index in _hearts.size():
		_hearts[index].modulate = HEART_DIM_COLOR if index >= current else Color.WHITE


func _build_hearts(count: int) -> void:
	if _hearts_box == null or _hearts.size() == count:
		return
	for heart in _hearts:
		_hearts_box.remove_child(heart)
		heart.queue_free()
	_hearts.clear()
	var texture := load(HEART_TEXTURE_PATH) as Texture2D
	for _index in count:
		var heart := TextureRect.new()
		heart.texture = texture
		heart.custom_minimum_size = HEART_DISPLAY_SIZE
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts_box.add_child(heart)
		_hearts.append(heart)


## The level may assemble the HUD scene without these children; build a usable fallback.
func _build_missing_nodes() -> void:
	if _hearts_box == null:
		_hearts_box = HBoxContainer.new()
		_hearts_box.name = "Hearts"
		_hearts_box.position = HEARTS_ORIGIN
		_hearts_box.add_theme_constant_override("separation", HEART_SEPARATION)
		_hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hearts_box)
	if _coin_icon != null and _soul_label != null:
		return
	var soul_root := get_node_or_null("Soul") as CanvasItem
	if soul_root == null:
		var created := Control.new()
		created.name = "Soul"
		created.position = SOUL_ORIGIN
		created.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(created)
		soul_root = created
	if _coin_icon == null:
		var icon := TextureRect.new()
		icon.name = "CoinIcon"
		icon.texture = load(COIN_TEXTURE_PATH) as Texture2D
		icon.custom_minimum_size = COIN_DISPLAY_SIZE
		icon.size = COIN_DISPLAY_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		soul_root.add_child(icon)
		_coin_icon = icon
	if _soul_label == null:
		var label := Label.new()
		label.name = "SoulLabel"
		label.position = SOUL_LABEL_OFFSET
		label.text = "0"
		label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		soul_root.add_child(label)
		_soul_label = label
