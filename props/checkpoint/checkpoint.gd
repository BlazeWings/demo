class_name Checkpoint
extends Area2D


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(&"interactable")


func interact() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		var health := player.get_node_or_null("Components/HealthComponent") as HealthComponent
		if health != null:
			health.reset_health()
		else:
			push_warning("[Checkpoint] interact(): %s 上找不到 Components/HealthComponent，未回血" % player.name)
	GameManager.set_respawn(global_position)
