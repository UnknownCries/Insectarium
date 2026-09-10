class_name HeartPickup
extends Area2D

## Heal pickup: restores a fixed amount of health to the player on touch,
## then disappears. Ignored at full health - stays on the ground instead of
## being silently wasted, so the player can come back for it later.

@export var heal_amount: int = 2

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.health >= body.max_health:
		return
	if body.has_method("heal"):
		body.heal(heal_amount)
	queue_free()
