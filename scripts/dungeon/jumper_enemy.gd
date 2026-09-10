class_name JumperEnemy
extends Enemy

## Jump-and-land enemy: sits GROUNDED (vulnerable) for ground_duration, then
## leaps toward the player - invisible and intangible with a landing
## telegraph - and deals a contact hit on landing if the player is still
## within landing_damage_radius. Never chases; the jump is its only attack.
##
## Must extend Enemy: RoomSceneBase._spawn_enemies_safely() does
## `selected_scene.instantiate() as Enemy` and silently drops anything that
## isn't an Enemy subclass. _physics_process() is fully overridden with its
## own state machine, so Enemy's pathfinding/separation/surround exports go
## unused here.

enum JumpState { GROUNDED, AIRBORNE }

@export var telegraph_scene: PackedScene

@export_group("Jump Cycle")
@export var ground_duration: float = 1.2  # grounded + vulnerable time between jumps
@export var air_time: float = 0.7         # invisible/intangible time spent airborne

@export_group("Landing Hit")
@export var landing_damage_radius: float = 24.0  # player caught this close to the landing spot takes a hit

var jump_state: JumpState = JumpState.GROUNDED
var state_timer: float = 0.0
var landing_target: Vector2 = Vector2.ZERO
var active_telegraph: Node2D = null

@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	super._ready()
	state_timer = ground_duration

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if is_spawn_frozen(delta):
		return

	match jump_state:
		JumpState.GROUNDED:
			_update_grounded(delta)
		JumpState.AIRBORNE:
			_update_airborne(delta)

func _update_grounded(delta: float) -> void:
	state_timer -= delta
	SpriteFacing.apply(visual, player.global_position - global_position)
	if state_timer <= 0.0:
		_enter_airborne()

func _enter_airborne() -> void:
	jump_state = JumpState.AIRBORNE
	state_timer = air_time
	landing_target = player.global_position

	visible = false
	collision_shape.disabled = true

	if telegraph_scene != null:
		active_telegraph = telegraph_scene.instantiate()
		var parent := get_parent()
		if parent != null:
			parent.add_child(active_telegraph)
			active_telegraph.global_position = landing_target
			if active_telegraph.has_method("start"):
				active_telegraph.start(air_time)

func _update_airborne(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_enter_grounded()

func _enter_grounded() -> void:
	_clear_telegraph()

	global_position = landing_target
	visible = true
	collision_shape.disabled = false

	# Reuses Enemy's own attack_damage export rather than adding a new one.
	if player.global_position.distance_to(landing_target) <= landing_damage_radius:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)

	jump_state = JumpState.GROUNDED
	state_timer = ground_duration

func _clear_telegraph() -> void:
	if active_telegraph != null and is_instance_valid(active_telegraph):
		active_telegraph.queue_free()
	active_telegraph = null
