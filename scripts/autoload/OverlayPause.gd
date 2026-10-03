extends Node
## SceneTree.paused refcount. Overlays must never write `paused` directly
## or closing one sheet can unpause the run under another.

var _depth: int = 0


func push() -> void:
	_depth += 1
	get_tree().paused = true


func pop() -> void:
	_depth = maxi(_depth - 1, 0)
	get_tree().paused = _depth > 0


func reset() -> void:
	_depth = 0
	get_tree().paused = false
