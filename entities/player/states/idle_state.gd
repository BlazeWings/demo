class_name PlayerIdleState
extends PlayerGroundedState


func enter() -> void:
	player.reset_dashes()
	player.play_anim(&"idle")
