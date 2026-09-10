class_name SpriteFacing
extends RefCounted

## Every hand-drawn sprite faces "up" (top of image = front), but Godot's
## rotation 0 faces right - so aligning the two needs a +90 degree (PI/2)
## offset, centralized here.
static func apply(visual: Node2D, dir: Vector2) -> void:
	if dir.length() > 0.01:
		visual.rotation = dir.angle() + PI / 2.0
