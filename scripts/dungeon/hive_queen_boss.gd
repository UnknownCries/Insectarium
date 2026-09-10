class_name HiveQueenBoss
extends CharacterBody2D

## Boss with no attack of its own - only summons minions. Self-contained:
## room_scene_base.gd's _spawn_boss positions this node, calls
## set_astar_grid() on it, and add_child()s it.
##
## Movement is a slow, player-agnostic hover to a random walkable point.
## The only "attack" is summon_cooldown-gated waves of attack minions
## (melee_enemy.tscn, unmodified) and guard minions (BossGuardMinion,
## orbiting as a physical shield). take_damage() sweeps any minions left
## alive in spawned_minions before emitting `defeated`, so none are left
## wandering the unlocked room.

signal defeated

@export var max_health: int = 20
@export var attack_minion_scene: PackedScene
@export var guard_minion_scene: PackedScene
@export var spawn_freeze_duration: float = 0.5

@export_group("Summoning")
@export var summon_cooldown: float = 5.0
@export var attack_minions_per_wave: int = 2
@export var guard_minions_per_wave: int = 2
@export var max_concurrent_minions: int = 6  # hard cap so waves can't stack up faster than the player can clear them
@export var minion_spawn_scatter: float = 20.0  # random offset so a wave doesn't spawn stacked exactly on top of the boss

@export_group("Hover")
@export var hover_speed: float = 50.0
@export var hover_retarget_min: float = 2.0
@export var hover_retarget_max: float = 4.0

@export_group("Guards")
@export var guard_orbit_radius: float = 32.0
@export var guard_orbit_speed: float = 1.0

var health: int
var player: Node2D = null
var astar_ref: AStarGrid2D = null
var spawn_freeze_timer: float = 0.0
var summon_timer: float = 0.0
var hover_target: Vector2 = Vector2.ZERO
var hover_retarget_timer: float = 0.0
var spawned_minions: Array = []

@onready var visual: Sprite2D = $Visual

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	spawn_freeze_timer = spawn_freeze_duration
	summon_timer = summon_cooldown  # full cooldown so the first wave doesn't fire immediately

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D

	hover_target = position
	hover_retarget_timer = 0.0

func set_astar_grid(grid: AStarGrid2D) -> void:
	astar_ref = grid

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

	_update_hover(delta)
	_update_summon(delta)

## Player-agnostic wander: pick a random walkable point, seek toward it,
## re-pick on arrival, on a timeout, or after bumping into something.
func _update_hover(delta: float) -> void:
	hover_retarget_timer -= delta
	var arrived := position.distance_to(hover_target) < 8.0
	if hover_retarget_timer <= 0.0 or arrived:
		hover_target = _pick_random_hover_point()
		hover_retarget_timer = randf_range(hover_retarget_min, hover_retarget_max)

	var to_target := hover_target - position
	if to_target.length() > 4.0:
		velocity = to_target.normalized() * hover_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	SpriteFacing.apply(visual, velocity)

	if get_slide_collision_count() > 0:
		hover_retarget_timer = 0.0

## Samples random cells in the room's walkable A* grid and returns the
## first walkable one's center; falls back to the boss's current position.
func _pick_random_hover_point() -> Vector2:
	if astar_ref == null:
		return position

	var region := astar_ref.region
	if region.size.x <= 2 or region.size.y <= 2:
		return position

	var grid_step := 24.0
	var max_tries := 10
	for i in range(max_tries):
		var gx := region.position.x + 1 + randi() % (region.size.x - 2)
		var gy := region.position.y + 1 + randi() % (region.size.y - 2)
		var cell := Vector2i(gx, gy)
		if not astar_ref.is_point_solid(cell):
			return Vector2(cell) * grid_step + Vector2(grid_step / 2.0, grid_step / 2.0)

	return position

func _update_summon(delta: float) -> void:
	summon_timer -= delta
	if summon_timer > 0.0:
		return
	summon_timer = summon_cooldown

	spawned_minions = spawned_minions.filter(func(m): return is_instance_valid(m))

	var slots_left := max_concurrent_minions - spawned_minions.size()
	if slots_left <= 0:
		return

	var attack_count: int = mini(attack_minions_per_wave, slots_left)
	slots_left -= attack_count
	var guard_count: int = mini(guard_minions_per_wave, slots_left)

	for i in range(attack_count):
		_spawn_attack_minion()
	for i in range(guard_count):
		_spawn_guard_minion()

func _spawn_offset() -> Vector2:
	return Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * minion_spawn_scatter

func _spawn_attack_minion() -> void:
	if attack_minion_scene == null:
		return

	var minion := attack_minion_scene.instantiate()
	minion.position = position + _spawn_offset()
	if astar_ref != null and minion.has_method("set_astar_grid"):
		minion.set_astar_grid(astar_ref)

	_register_minion(minion)

func _spawn_guard_minion() -> void:
	if guard_minion_scene == null:
		return

	var minion := guard_minion_scene.instantiate()
	minion.position = position + _spawn_offset()
	if minion is BossGuardMinion:
		var guard := minion as BossGuardMinion
		guard.boss = self
		guard.orbit_radius = guard_orbit_radius
		guard.orbit_speed = guard_orbit_speed

	_register_minion(minion)

## Shared bookkeeping for both minion types: parent onto the same room this
## boss is a child of (keeps Enemy's chase math correct) and track it for
## the max_concurrent_minions cap and take_damage()'s cleanup sweep.
func _register_minion(minion: Node) -> void:
	spawned_minions.append(minion)
	if minion.has_signal("died"):
		minion.died.connect(_on_minion_died.bind(minion))

	var room := get_parent()
	if room == null:
		spawned_minions.erase(minion)
		minion.queue_free()
		return
	room.add_child(minion)

func _on_minion_died(minion: Node) -> void:
	spawned_minions.erase(minion)

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		for minion in spawned_minions:
			if is_instance_valid(minion):
				minion.queue_free()
		spawned_minions.clear()
		defeated.emit()
		queue_free()
