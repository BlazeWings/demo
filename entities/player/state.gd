class_name PlayerState
extends Node

## 玩家状态基类（node-based FSM，契约 §4）。
## 由 PlayerStateMachine 注入 player / state_machine，physics_update 返回目标状态名或 ""。

var player: Player


func enter() -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> String:
	return ""
