class_name Hud
extends CanvasLayer

## Simple top-left HUD: an HP bar plus stat numbers below it. Finds the
## player via the "player" group (same pattern Enemy uses to find it) and
## re-checks each frame, so it stays correct even if the player is
## respawned/recreated.

## Game runs at a 320x180 viewport (stretched up to fill the window), so
## the HUD is sized to fit that, not screen pixels.
const HP_BAR_WIDTH: float = 70.0

@onready var hp_fill: ColorRect = $Control/VBox/HPBar/Fill
@onready var hp_label: Label = $Control/VBox/HPBar/HPLabel
@onready var damage_label: Label = $Control/VBox/DamageLabel
@onready var fire_rate_label: Label = $Control/VBox/FireRateLabel
@onready var speed_label: Label = $Control/VBox/SpeedLabel
@onready var range_label: Label = $Control/VBox/RangeLabel

var player: Player = null

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = null
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0] as Player
		if player == null:
			return

	_update_display()

func _update_display() -> void:
	var fraction := 0.0
	if player.max_health > 0:
		fraction = float(player.health) / float(player.max_health)
	fraction = clampf(fraction, 0.0, 1.0)

	hp_fill.size.x = HP_BAR_WIDTH * fraction
	hp_label.text = "%d / %d" % [player.health, player.max_health]

	damage_label.text = "Damage: %d" % player.damage
	var shots_per_sec := (1.0 / player.fire_rate) if player.fire_rate > 0.0 else 0.0
	fire_rate_label.text = "Fire Rate: %.1f/s" % shots_per_sec
	speed_label.text = "Speed: %d" % int(round(player.speed))
	range_label.text = "Range: %d" % int(round(player.attack_range))
