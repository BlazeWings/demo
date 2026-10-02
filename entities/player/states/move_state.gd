class_name PlayerMoveState
extends PlayerGroundedState


func enter() -> void:
	player.reset_dashes()
	player.play_anim(&"run")


func physics_update(delta: float) -> String:
	var next := super.physics_update(delta)
	if next.is_empty():
		player.play_anim(&"run" if player.is_moving_fast() else &"walk")
	return next
