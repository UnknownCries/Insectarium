class_name FleaBoss
extends CharacterBody2D

## Stationary ambush boss with no pathfinding/chase state. Attack loop:
##   IDLE (grounded, vulnerable) -> jump: go invisible + intangible ->
##   AIRBORNE (a landing telegraph grows at the player's captured position)
##   -> teleport onto that spot, reappear -> LANDING (brief beat) ->
##   SHOOTING (a fan of bullets) -> back to IDLE -> repeat.
## Self-contained: room_scene_base.gd's _spawn_boss() just positions this
## node and add_child()s it.

signal defeated

enum State { IDLE, AIRBORNE, LANDING, SHOOTING }

@export var max_health: int = 20
@export var bullet_scene: PackedScene
@export var telegraph_scene: PackedScene
@export var spawn_freeze_duration: float = 0.5

@export_group("Jump Cycle")
@export var idle_duration: float = 1.5   # grounded, vulnerable time before the next jump
@export var air_time: float = 1.0        # invisible/intangible time spent airborne
@export var landing_pause: float = 0.15  # brief beat after reappearing, before firing

@export_group("Landing Hit")
@export var landing_damage_radius: float = 24.0  # player caught this close to the landing spot takes a hit
@export var landing_contact_damage: int = 1

@export_group("Bullet Volley")
@export var bullet_count: int = 5
@export var bullet_spread_degrees: float = 60.0

var health: int
var player: Node2D = null
var spawn_freeze_timer: float = 0.0
var current_state: State = State.IDLE
var state_timer: float = 0.0
var landing_target: Vector2 = Vector2.ZERO
var active_telegraph: Node2D = null

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Sprite2D = $Visual

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	spawn_freeze_timer = spawn_freeze_duration
	state_timer = idle_duration

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D

func is_spawn_frozen(delta: float) -> bool:
	if spawn_freeze_timer <= 0.0:
		return false
	spawn_freeze_timer -= delta
	velocity = Vector2.ZERO
	move_and_slide()
	return true

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if is_spawn_frozen(delta):
		return

	match current_state:
		State.IDLE:
			_update_idle(delta)
		State.AIRBORNE:
			_update_airborne(delta)
		State.LANDING:
			_update_landing(delta)
		State.SHOOTING:
			pass  # resolved synchronously inside _enter_shooting(), never sits here

func _update_idle(delta: float) -> void:
	state_timer -= delta
	SpriteFacing.apply(visual, player.global_position - global_position)
	if state_timer <= 0.0:
		_enter_airborne()

## Captures the player's current position as the landing spot, goes
## invisible and intangible, and spawns a telegraph there as warning.
func _enter_airborne() -> void:
	current_state = State.AIRBORNE
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
		_enter_landing()

func _enter_landing() -> void:
	_clear_telegraph()

	global_position = landing_target
	visible = true
	collision_shape.disabled = false

	# Contact hit if the player is still in the telegraphed spot on landing.
	if player.global_position.distance_to(landing_target) <= landing_damage_radius:
		if player.has_method("take_damage"):
			player.take_damage(landing_contact_damage)

	current_state = State.LANDING
	state_timer = landing_pause

func _update_landing(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_enter_shooting()

func _enter_shooting() -> void:
	current_state = State.SHOOTING
	_fire_volley()
	current_state = State.IDLE
	state_timer = idle_duration

## Fires bullet_count bullets in an even fan spread centered on the
## direction to the player.
func _fire_volley() -> void:
	if bullet_scene == null or player == null:
		return

	var base_dir := (player.global_position - global_position).normalized()
	if base_dir == Vector2.ZERO:
		base_dir = Vector2.RIGHT

	var spread_rad := deg_to_rad(bullet_spread_degrees)
	for i in range(bullet_count):
		var t := 0.5 if bullet_count == 1 else float(i) / float(bullet_count - 1)
		var angle_offset := lerpf(-spread_rad / 2.0, spread_rad / 2.0, t)
		var dir := base_dir.rotated(angle_offset)

		var bullet := bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = global_position
		if bullet.has_method("setup"):
			bullet.setup(dir, self)

func _clear_telegraph() -> void:
	if active_telegraph != null and is_instance_valid(active_telegraph):
		active_telegraph.queue_free()
	active_telegraph = null

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		_clear_telegraph()
		defeated.emit()
		queue_free()
