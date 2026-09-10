class_name ItemPickup
extends Area2D

## Stat-up pickup: grants one random, modest buff to the player on touch,
## then disappears. Icon shown is picked per buff_type from BUFF_ICONS.

enum BuffType { MAX_HEALTH, DAMAGE, SPEED, FIRE_RATE, RANGE }

const BUFF_ICONS := {
	BuffType.MAX_HEALTH: preload("res://assets/sprites/pickups/health_up.png"),
	BuffType.DAMAGE: preload("res://assets/sprites/pickups/attack_up.png"),
	BuffType.SPEED: preload("res://assets/sprites/pickups/speed_up.png"),
	BuffType.FIRE_RATE: preload("res://assets/sprites/pickups/fire_rate_up.png"),
	BuffType.RANGE: preload("res://assets/sprites/pickups/range_up.png"),
}

@onready var visual: Sprite2D = $Visual

var buff_type: BuffType

func _ready() -> void:
	buff_type = BUFF_ICONS.keys()[randi() % BUFF_ICONS.size()]
	visual.texture = BUFF_ICONS[buff_type]
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_apply_buff(body)
	queue_free()

func _apply_buff(player: Node) -> void:
	match buff_type:
		BuffType.MAX_HEALTH:
			# +2 = one full heart, matching heart_pickup.gd's own
			# heal_amount now that health is in half-heart units.
			player.max_health += 2
			player.health = mini(player.health + 2, player.max_health)
			if player.has_signal("health_changed"):
				player.health_changed.emit(player.health, player.max_health)
		BuffType.DAMAGE:
			player.damage += 1
		BuffType.SPEED:
			player.speed += 15.0
		BuffType.FIRE_RATE:
			player.fire_rate = maxf(player.fire_rate * 0.85, 0.15)
		BuffType.RANGE:
			player.attack_range += 30.0
