extends Area2D


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player") and body.has_method(&"on_hazard"):
		body.call(&"on_hazard")
		return
	body.queue_free()
