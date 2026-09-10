class_name Bullet
extends Area2D

@export var speed: float = 200.0
@export var damage: int = 1
@export var max_distance: float = 0.0  # 0 = unlimited range

var direction: Vector2 = Vector2.ZERO
var shooter: Node2D = null
var _traveled: float = 0.0

@onready var visual: Sprite2D = $Visual

func setup(dir: Vector2, source: Node2D = null) -> void:
	direction = dir
	shooter = source

func _ready() -> void:
	# Pinned back to PAUSABLE so bullets don't inherit DungeonRoot's ALWAYS
	# and keep flying while the game is paused.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("bullets")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# setup() already ran (called right after instantiate(), before
	# add_child()), so `direction` is populated here. Never turns mid-flight.
	SpriteFacing.apply(visual, direction)

func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	position += step

	if max_distance > 0.0:
		_traveled += step.length()
		if _traveled >= max_distance:
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Ignore whoever fired this bullet (prevents self-damage on spawn)
	if body == shooter:
		return

	# Ignore bullets hitting members of the same faction as the shooter
	if shooter != null and _same_faction(body, shooter):
		return

	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()  # consumed on any solid hit, not just damageable ones

func _same_faction(a: Node2D, b: Node2D) -> bool:
	if a.is_in_group("player") and b.is_in_group("player"):
		return true
	if a.is_in_group("enemies") and b.is_in_group("enemies"):
		return true
	return false

func _on_area_entered(area: Area2D) -> void:
	if area == shooter:
		return

	if area.has_method("take_damage"):
		area.take_damage(damage)
	queue_free()
