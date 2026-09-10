class_name HoleToNextFloor
extends Area2D

## Trapdoor to the next floor. Touching it asks the main scene to advance
## the floor, duck-typed via has_method("advance_to_next_floor").
##
## Starts CLOSED if the player is already standing on it the instant it
## spawns (boss killed dead center) - otherwise the floor would transition
## the same frame with no chance to react. Opens the moment the player
## steps off, and stays open.

const CLOSED_TEXTURE := preload("res://assets/sprites/pickups/closed_hole.png")
const OPEN_TEXTURE := preload("res://assets/sprites/pickups/open_hole.png")

var _triggered: bool = false
var _open: bool = true

@onready var visual: Sprite2D = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if _player_already_here():
		_open = false

	_apply_visual()

## A brand-new Area2D hasn't been evaluated by the physics server yet, so
## get_overlapping_bodies() would unreliably read empty - a direct distance
## check against the player's position doesn't depend on that timing.
func _player_already_here() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	var player := players[0] as Node2D
	if player == null:
		return false

	# A real overlap is circle-vs-circle against BOTH shapes, not just the hole's.
	var hole_radius := 10.0
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		hole_radius = (collision_shape.shape as CircleShape2D).radius

	var player_radius := 8.0
	var player_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if player_shape != null and player_shape.shape is CircleShape2D:
		player_radius = (player_shape.shape as CircleShape2D).radius

	return global_position.distance_to(player.global_position) <= hole_radius + player_radius

func _apply_visual() -> void:
	if visual != null:
		visual.texture = OPEN_TEXTURE if _open else CLOSED_TEXTURE

func _on_body_entered(body: Node2D) -> void:
	if _triggered or not _open or not body.is_in_group("player"):
		return
	_triggered = true

	var root := get_tree().current_scene
	if root != null and root.has_method("advance_to_next_floor"):
		root.advance_to_next_floor()

func _on_body_exited(body: Node2D) -> void:
	if not _open and body.is_in_group("player"):
		_open = true
		_apply_visual()
