extends Node

## 叠发截断令牌：hitstop 叠加时只认最后一次，避免先到的计时器提前把减速清掉。
var _generation: int = 0


func hitstop(duration: float = 0.06, scale: float = 0.05) -> void:
	Engine.time_scale = scale
	_generation += 1
	var my_gen := _generation
	await get_tree().create_timer(duration, true, false, true).timeout
	if my_gen == _generation:
		Engine.time_scale = 1.0
