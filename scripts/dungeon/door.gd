class_name Door
extends StaticBody2D

@onready var collider: CollisionShape2D = $CollisionShape2D
@onready var visual: ColorRect = $ColorRect

var is_locked: bool = false

func lock() -> void:
	is_locked = true
	visible = true
	collider.set_deferred("disabled", false)

func unlock() -> void:
	is_locked = false
	visible = false
	collider.set_deferred("disabled", true)
