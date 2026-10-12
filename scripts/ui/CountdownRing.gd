class_name CountdownRing
extends Control
## A dark disc with an icon in the middle and a red ring that drains clockwise from the top.
## `progress` 1 = full ring, 0 = empty. Used by the bribe offer.

const TRACK := Color(0.05, 0.06, 0.12, 0.9)
const RING := Color(1.0, 0.24, 0.3, 1.0)
const RING_DIM := Color(0.35, 0.1, 0.14, 1.0)
const WIDTH: float = 12.0

var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()
var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - WIDTH
	draw_circle(c, r + WIDTH * 0.5, TRACK)
	draw_arc(c, r, 0.0, TAU, 64, RING_DIM, WIDTH, true)
	if progress > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, RING, WIDTH, true)
	if icon:
		var side: float = r * 1.45
		draw_texture_rect(icon, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
