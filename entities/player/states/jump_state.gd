class_name PlayerJumpState
extends PlayerAirborneState


func enter() -> void:
	player.do_jump()
	player.freeze_frame(&"run", 2)


func physics_update(delta: float) -> String:
	var next := super.physics_update(delta)
	if not next.is_empty():
		return next
	if player.velocity.y >= 0.0:
		return PlayerStateMachine.FALL
	return ""
