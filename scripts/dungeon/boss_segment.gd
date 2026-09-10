class_name BossSegment
extends CharacterBody2D

## One piece of a WormBoss chain. Has no AI of its own - WormBoss drives
## the head's movement and every other segment's position directly. This
## node only owns its own health/visual/collision so it can be shot and
## destroyed independently.

signal segment_died(segment: BossSegment)

const HEAD_TEXTURE := preload("res://assets/sprites/bosses/worm_boss/worm_head.png")
const BODY_TEXTURE := preload("res://assets/sprites/bosses/worm_boss/worm_body.png")

@export var max_health: int = 3
@export var is_head: bool = false
@export var segment_radius: float = 8.0
@export var contact_damage: int = 1
@export var contact_cooldown: float = 1.0

var health: int
var player: Node2D = null
var contact_timer: float = 0.0

@onready var visual: Sprite2D = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	refresh_visual()

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D

## Every segment is a hazard on touch, not just the head. Body segments
## never call move_and_slide() (WormBoss repositions them directly), so a
## plain distance check against the player, on a cooldown, stands in for
## enemy.gd's slide-collision-based melee attack.
func _physics_process(delta: float) -> void:
	if player == null:
		return

	if contact_timer > 0.0:
		contact_timer -= delta
		return

	var reach := segment_radius + 10.0  # ~player radius (8) + a small buffer
	if global_position.distance_to(player.global_position) <= reach:
		if player.has_method("take_damage"):
			player.take_damage(contact_damage)
		contact_timer = contact_cooldown

## Re-applies texture/collision radius from the current export values.
## Called on spawn, and again whenever WormBoss promotes this segment to
## head, so its look stays in sync with its role.
func refresh_visual() -> void:
	if visual != null:
		visual.texture = HEAD_TEXTURE if is_head else BODY_TEXTURE

	if collision_shape != null:
		# A fresh shape, not a mutation of the one baked into the scene -
		# that sub-resource is shared across every instance of this scene,
		# so resizing it in place would resize every other segment too.
		var shape := CircleShape2D.new()
		shape.radius = segment_radius
		collision_shape.shape = shape

## Thin wrapper so WormBoss can rotate a segment without reaching into its
## internals directly.
func face_direction(dir: Vector2) -> void:
	SpriteFacing.apply(visual, dir)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		segment_died.emit(self)
		queue_free()
