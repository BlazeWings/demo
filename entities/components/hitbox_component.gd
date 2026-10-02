class_name HitboxComponent
extends Area2D

signal hit_landed()

@export var damage: int = 1
@export var knockback: float = 120.0

## 非空时只命中 owner（或祖先节点）属于该 group 的目标，防止自伤
@export var target_group: StringName = ""
## 监测的物理层：32 = 层6(hurtbox)，96 = 层6+层7(箭矢)
@export var target_mask: int = 32

var _hit_targets: Array[Area2D] = []


func _ready() -> void:
	collision_layer = 16
	collision_mask = target_mask
	monitorable = false
	monitoring = false
	area_entered.connect(_on_area_entered)


func set_active(active: bool) -> void:
	if active:
		_hit_targets.clear()
	monitoring = active


func _on_area_entered(area: Area2D) -> void:
	if not monitoring:
		return
	if _hit_targets.has(area):
		return
	if area is HurtboxComponent:
		# 组过滤只作用于受击体：箭矢不属于 "enemy" 组，但仍必须能被玩家打落
		if not _matches_target_group(area):
			return
		_hit_targets.append(area)
		# 动态调用：静态调用 receive_hit(self) 会让 MCP 校验器（剥离 class_name 后重新解析）误报参数类型错误
		area.call(&"receive_hit", self)
		hit_landed.emit()
	elif area.has_method(&"on_shot_down"):
		_hit_targets.append(area)
		area.call(&"on_shot_down")
		hit_landed.emit()


func _matches_target_group(area: Area2D) -> bool:
	if target_group == &"":
		return true
	var candidate: Node = area.owner
	if candidate == null:
		candidate = area.get_parent()
	while candidate != null:
		if candidate.is_in_group(target_group):
			return true
		candidate = candidate.get_parent()
	return false
