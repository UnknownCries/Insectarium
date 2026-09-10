class_name Enemy
extends CharacterBody2D

signal died

enum State { CHASE, ATTACK }

@export var max_health: int = 2
@export var speed: float = 65.0
@export var attack_range: float = 20.0
@export var attack_damage: int = 1
@export var attack_cooldown: float = 1.0
@export var path_recalc_interval: float = 0.2  # Recalculate path 5 times per second

@export_group("Separation")
@export var separation_radius: float = 20.0
@export var separation_strength: float = 40.0
@export var separation_weight: float = 0.5  # how much separation can affect final direction, 0-1

@export_group("Stuck Detection")
@export var stuck_check_interval: float = 0.5
@export var stuck_distance_threshold: float = 4.0  # min distance expected to travel in that time

@export_group("Surround")
@export var surround_radius: float = 18.0  # distance from the player each enemy aims to stand at when part of a group
@export var surround_engage_radius: float = 250.0  # peers farther than this from the player don't affect anyone's slot

@export_group("Spawn")
@export var spawn_freeze_duration: float = 0.5  # seconds an enemy sits idle right after spawning, giving the player time to react

var current_state: State = State.CHASE
var health: int
var player: Node2D = null
var attack_timer: float = 0.0
var recalc_timer: float = 0.0

var current_path: PackedVector2Array = []
var path_index: int = 0
var astar_ref: AStarGrid2D = null

var stuck_timer: float = 0.0
var last_stuck_check_pos: Vector2 = Vector2.ZERO
var is_forced_repath: bool = false
var spawn_freeze_timer: float = 0.0

@onready var visual: Sprite2D = $Visual

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	last_stuck_check_pos = position
	spawn_freeze_timer = spawn_freeze_duration

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D

## True while the enemy is still frozen right after spawning. Subclasses
## that override _physics_process entirely (RangedEnemy) should check this
## themselves before doing anything else.
func is_spawn_frozen(delta: float) -> bool:
	if spawn_freeze_timer <= 0.0:
		return false
	spawn_freeze_timer -= delta
	velocity = Vector2.ZERO
	move_and_slide()
	queue_redraw()
	return true

func set_astar_grid(grid: AStarGrid2D) -> void:
	astar_ref = grid

# Distinct angular slot around the player so multiple enemies converging
# at once fan out into a ring instead of pathing to the same tile. Only
# enemies actually near the player count as peers, and each slot is
# anchored to that enemy's own bearing to the player.
func _get_surround_offset() -> Vector2:
	if player == null:
		return Vector2.ZERO

	var peers: Array = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Node2D and (node as Node2D).global_position.distance_to(player.global_position) <= surround_engage_radius:
			peers.append(node)

	if peers.size() <= 1:
		return Vector2.ZERO

	peers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var index := peers.find(self)
	if index == -1:
		return Vector2.ZERO

	var my_bearing := (global_position - player.global_position).angle()
	var spread := TAU / float(peers.size())
	var angle := my_bearing + spread * (float(index) - float(peers.size() - 1) / 2.0)
	return Vector2(cos(angle), sin(angle)) * surround_radius

# Chase/pathfinding target, in the room's local space: the player's position
# offset by this enemy's surround slot. State transitions (attack range,
# line of sight, etc.) should keep using player.global_position directly -
# only the approach target uses this.
func _get_chase_target_local() -> Vector2:
	var local_player_pos: Vector2 = get_parent().to_local(player.global_position)
	if astar_ref == null:
		return get_parent().to_local(player.global_position + _get_surround_offset())

	var local_target: Vector2 = get_parent().to_local(player.global_position + _get_surround_offset())
	var cell := Vector2i(floor(local_target.x / 24.0), floor(local_target.y / 24.0))

	if not astar_ref.is_in_boundsv(cell):
		return local_player_pos

	if astar_ref.is_point_solid(cell):
		var resolved := _get_nearest_walkable_cell(cell)
		if astar_ref.is_point_solid(resolved):
			# Surround slot is buried in a wall/obstacle with no walkable
			# cell nearby - fall back to the player's own position, which
			# is always reachable, instead of chasing a dead end.
			return local_player_pos

	return local_target

func _physics_process(delta: float) -> void:
	if player == null:
		return

	if is_spawn_frozen(delta):
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	recalc_timer -= delta
	if recalc_timer <= 0.0:
		recalc_timer = path_recalc_interval
		_recalculate_path()

	_check_if_stuck(delta)

	var dist_to_player := global_position.distance_to(player.global_position)

	match current_state:
		State.CHASE:
			if dist_to_player <= attack_range:
				current_state = State.ATTACK
			else:
				_follow_astar_path(delta)

		State.ATTACK:
			if dist_to_player > attack_range * 1.5:
				current_state = State.CHASE
			else:
				_perform_melee_attack()

	var facing_dir := velocity if current_state == State.CHASE else (player.global_position - global_position)
	SpriteFacing.apply(visual, facing_dir)

	# Redraw debug path overlay every physics tick
	queue_redraw()

func _get_nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if astar_ref.is_in_boundsv(cell) and not astar_ref.is_point_solid(cell):
		return cell

	# Expanding ring search - an enemy can drift several cells deep into the
	# padded (pathfinding-only) buffer around an obstacle corner. Kept
	# modest since the resolved cell becomes a straight-line target with no
	# obstacle-avoidance of its own.
	var max_radius := 3  # up to 72px out
	for radius in range(1, max_radius + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only the outer ring of this radius - inner rings already checked
				var check_cell: Vector2i = cell + Vector2i(dx, dy)
				if astar_ref.is_in_boundsv(check_cell) and not astar_ref.is_point_solid(check_cell):
					return check_cell
	return cell

func _recalculate_path() -> void:
	if astar_ref == null or player == null or get_parent() == null:
		return

	var local_enemy_pos: Vector2 = position
	var local_player_pos: Vector2 = _get_chase_target_local()

	var start_cell := Vector2i(floor(local_enemy_pos.x / 24.0), floor(local_enemy_pos.y / 24.0))
	var end_cell := Vector2i(floor(local_player_pos.x / 24.0), floor(local_player_pos.y / 24.0))

	if not (astar_ref.is_in_boundsv(start_cell) and astar_ref.is_in_boundsv(end_cell)):
		return

	# Resolve to walkable substitutes first, so a target on a solid margin
	# cell consistently resolves to the same walkable neighbor instead of
	# forcing a full repath every recalc tick.
	if astar_ref.is_point_solid(start_cell):
		start_cell = _get_nearest_walkable_cell(start_cell)

	if astar_ref.is_point_solid(end_cell):
		end_cell = _get_nearest_walkable_cell(end_cell)

	# Handle same-cell movement gracefully
	if start_cell == end_cell:
		current_path = PackedVector2Array([local_player_pos])
		path_index = 0
		return

	if not is_forced_repath and not current_path.is_empty() and path_index < current_path.size():
		var last_target_cell: Vector2i = Vector2i(floor(current_path[current_path.size() - 1].x / 24.0), floor(current_path[current_path.size() - 1].y / 24.0))
		var cell_delta: Vector2i = last_target_cell - end_cell
		# Tolerate the target drifting into a neighboring cell rather than
		# demanding an exact match, since a fast-moving target crosses cell
		# boundaries almost every recalc tick.
		if absi(cell_delta.x) <= 1 and absi(cell_delta.y) <= 1:
			return

	is_forced_repath = false

	var new_path: PackedVector2Array = astar_ref.get_point_path(start_cell, end_cell)
	
	if new_path.is_empty():
		current_path = []
		path_index = 0
		return

	current_path = new_path
	# current_path[0] is always the start cell's own center - somewhere the
	# enemy is already at or very near - so heading there first buys
	# nothing and can even mean stepping backward toward it for a tick.
	# Skip straight to the next real waypoint when there is one.
	path_index = 1 if new_path.size() > 1 else 0

func _check_if_stuck(delta: float) -> void:
	stuck_timer += delta
	if stuck_timer < stuck_check_interval:
		return

	var moved := position.distance_to(last_stuck_check_pos)
	stuck_timer = 0.0
	last_stuck_check_pos = position

	if current_state == State.CHASE and moved < stuck_distance_threshold:
		is_forced_repath = true
		recalc_timer = 0.0

func _follow_astar_path(delta: float) -> void:
	var move_dir := Vector2.ZERO

	if current_path.is_empty() or path_index >= current_path.size():
		var local_player_pos: Vector2 = _get_chase_target_local()
		var to_player: Vector2 = local_player_pos - position
		if to_player.length() > 1.0:
			move_dir = to_player.normalized()
		else:
			move_dir = Vector2.ZERO
		if move_dir == Vector2.ZERO:
			recalc_timer = 0.0
	else:
		var target_point: Vector2 = current_path[path_index]
		if position.distance_to(target_point) < 12.0:
			path_index += 1
			if path_index < current_path.size():
				target_point = current_path[path_index]
			else:
				target_point = position

		move_dir = (target_point - position).normalized()

	var separation := _get_separation_direction()
	var blended_dir := (move_dir + separation * separation_weight)
	if blended_dir.length() > 0.01:
		blended_dir = blended_dir.normalized()
	else:
		blended_dir = move_dir

	velocity = blended_dir * speed
	move_and_slide()

func _get_separation_direction() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Node2D):
			continue
		var other_pos: Vector2 = (other as Node2D).global_position
		var offset := global_position - other_pos
		var dist := offset.length()
		if dist > 0.0 and dist < separation_radius:
			push += offset.normalized() * (separation_radius - dist) / separation_radius

	if push.length() > 1.0:
		push = push.normalized()
	return push

func _perform_melee_attack() -> void:
	var separation := _get_separation_direction()
	velocity = separation * speed * separation_weight
	if attack_timer <= 0.0:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)
		attack_timer = attack_cooldown
	move_and_slide()

func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		died.emit()
		queue_free()
