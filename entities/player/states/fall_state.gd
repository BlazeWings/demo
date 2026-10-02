class_name PlayerFallState
extends PlayerAirborneState


func enter() -> void:
	player.freeze_frame(&"run", 4)
	player.set_squash(0.92, 1.08)


func physics_update(delta: float) -> String:
	return super.physics_update(delta)
