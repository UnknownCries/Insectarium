extends Node2D

const ItemPickupScene := preload("res://item_pickup.tscn")
const HeartPickupScene := preload("res://heart_pickup.tscn")
const HoleToNextFloorScene := preload("res://hole_to_next_floor.tscn")

@export var cell_size: Vector2 = Vector2(320, 180)
@export var enemy_pool: Array[PackedScene] = []
@export var enemies_per_room_min: int = 2
@export var enemies_per_room_max: int = 3
@export var boss_pool: Array[PackedScene] = []
@export var heart_drop_chance: float = 0.5
@export var hole_offset_from_item: Vector2 = Vector2(0, -48)
@export var lock_dwell_time: float = 0.2

@onready var visuals: Node2D = $Visuals
@onready var walls: StaticBody2D = $Walls
@onready var door_markers: Node2D = $DoorMarkers
@onready var obstacles: Node2D = $Obstacles

var active_enemies: int = 0
var room_cleared: bool = false
var room_locked: bool = false
var current_placed_room: PlacedRoom
var astar: AStarGrid2D
var _dwell_timer: float = 0.0

func _process(delta: float) -> void:
	if _dwell_timer <= 0.0:
		return
	_dwell_timer -= delta
	if _dwell_timer <= 0.0:
		lock_room()

## tile_set: floor TileSet (see dungeon_builder.gd), passed straight through
## to RoomAutoBuilder.build().
func setup_room(room: PlacedRoom, tile_set: TileSet = null) -> void:
	current_placed_room = room
	RoomAutoBuilder.build(visuals, walls, walls, door_markers, obstacles, room, cell_size, tile_set)
	_setup_astar_grid(room)

	# Mark room 0 as cleared immediately so doors stay open and no enemies spawn
	if room.id == 0:
		room_cleared = true
		return

	# Item rooms: no lock, no enemies - just place one pickup dead center
	# and treat the room as already cleared.
	if room.room_type == RoomTemplate.RoomType.ITEM:
		room_cleared = true
		_spawn_item(room)
		return

	_build_room_interior_detector(room)

func _spawn_item(room: PlacedRoom) -> void:
	var item := ItemPickupScene.instantiate()
	item.position = _room_center(room)
	add_child(item)

func _room_center(room: PlacedRoom) -> Vector2:
	var center := Vector2.ZERO
	for cell in room.template.footprint:
		center += (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
	center /= room.template.footprint.size()
	return center

func _spawn_boss(room: PlacedRoom) -> void:
	if boss_pool.is_empty():
		return

	# Prefer a boss that hasn't appeared yet this run (DungeonRoot tracks
	# that); falls back to the full pool once every entry has been used.
	var candidates := boss_pool
	var root := get_tree().current_scene
	if root != null and root.has_method("get_used_boss_scenes"):
		var used: Array = root.get_used_boss_scenes()
		var unused: Array[PackedScene] = boss_pool.filter(func(s): return not used.has(s))
		if not unused.is_empty():
			candidates = unused

	var chosen_scene: PackedScene = candidates.pick_random()
	if root != null and root.has_method("mark_boss_used"):
		root.mark_boss_used(chosen_scene)

	var boss := chosen_scene.instantiate()
	boss.position = _room_center(room)
	if boss.has_method("set_astar_grid"):
		boss.set_astar_grid(astar)
	if boss.has_signal("defeated"):
		boss.defeated.connect(_on_boss_defeated.bind(room))
	add_child(boss)

func _on_boss_defeated(room: PlacedRoom) -> void:
	_spawn_item(room)

	var hole := HoleToNextFloorScene.instantiate()
	hole.position = _room_center(room) + hole_offset_from_item
	add_child(hole)

	unlock_room()

func _spawn_heart(pos: Vector2) -> void:
	var heart := HeartPickupScene.instantiate()
	heart.position = pos
	add_child(heart)

func _setup_astar_grid(room: PlacedRoom) -> void:
	astar = AStarGrid2D.new()
	
	var min_cell := room.template.footprint[0]
	var max_cell := room.template.footprint[0]
	for c in room.template.footprint:
		min_cell.x = min(min_cell.x, c.x)
		min_cell.y = min(min_cell.y, c.y)
		max_cell.x = max(max_cell.x, c.x)
		max_cell.y = max(max_cell.y, c.y)

	var grid_step := 24.0
	var local_rect := Rect2(
		Vector2(min_cell) * cell_size,
		Vector2(max_cell - min_cell + Vector2i.ONE) * cell_size
	)

	var grid_origin := Vector2i(floor(local_rect.position.x / grid_step), floor(local_rect.position.y / grid_step))
	var grid_size := Vector2i(ceil(local_rect.size.x / grid_step), ceil(local_rect.size.y / grid_step))

	astar.region = Rect2i(grid_origin, grid_size)
	astar.cell_size = Vector2(grid_step, grid_step)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()

	# 1. Mark walls as solid (16px border around room cells)
	var footprint_set := {}
	for cell in room.template.footprint:
		footprint_set[cell] = true

	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var cell_center := Vector2(x * grid_step + 12.0, y * grid_step + 12.0)
			var room_cell := Vector2i(floor(cell_center.x / cell_size.x), floor(cell_center.y / cell_size.y))
			
			if not footprint_set.has(room_cell):
				astar.set_point_solid(Vector2i(x, y), true)
			else:
				var lx := fmod(cell_center.x, cell_size.x)
				var ly := fmod(cell_center.y, cell_size.y)
				if lx < 16.0 and not footprint_set.has(room_cell + Vector2i(-1, 0)):
					astar.set_point_solid(Vector2i(x, y), true)
				elif lx > (cell_size.x - 16.0) and not footprint_set.has(room_cell + Vector2i(1, 0)):
					astar.set_point_solid(Vector2i(x, y), true)
				elif ly < 16.0 and not footprint_set.has(room_cell + Vector2i(0, -1)):
					astar.set_point_solid(Vector2i(x, y), true)
				elif ly > (cell_size.y - 16.0) and not footprint_set.has(room_cell + Vector2i(0, 1)):
					astar.set_point_solid(Vector2i(x, y), true)

	# 2. Mark obstacles as solid with clearance padding. Must stay at exactly
	# the enemy's collision half-extent (8px) - more than that can seal
	# narrower corridors in *_pillars templates into unpathable halves.
	var enemy_padding := 8.0
	for child in obstacles.get_children():
		if child is Node2D:
			var obs_node := child as Node2D
			# Read the obstacle's actual collision size rather than guessing from its name.
			var obs_size := Vector2(24.0, 24.0)  # fallback if no shape found
			var col_shape := obs_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if col_shape != null and col_shape.shape is RectangleShape2D:
				obs_size = (col_shape.shape as RectangleShape2D).size
			var half_size := obs_size / 2.0 + Vector2(enemy_padding, enemy_padding)

			var obs_rect := Rect2(obs_node.position - half_size, half_size * 2.0)
			
			var min_gx := int(floor(obs_rect.position.x / grid_step))
			var max_gx := int(ceil(obs_rect.end.x / grid_step))
			var min_gy := int(floor(obs_rect.position.y / grid_step))
			var max_gy := int(ceil(obs_rect.end.y / grid_step))
			
			for gx in range(min_gx, max_gx):
				for gy in range(min_gy, max_gy):
					var pt := Vector2i(gx, gy)
					if astar.is_in_boundsv(pt):
						astar.set_point_solid(pt, true)

func _spawn_enemies_safely(room: PlacedRoom) -> void:
	if enemy_pool.is_empty() or astar == null:
		return

	# Collect all walkable (non-solid) grid points in the room
	var walkable_points: Array[Vector2i] = []
	for x in range(astar.region.position.x + 1, astar.region.end.x - 1):
		for y in range(astar.region.position.y + 1, astar.region.end.y - 1):
			var pt: Vector2i = Vector2i(x, y)
			if not astar.is_point_solid(pt):
				walkable_points.append(pt)

	if walkable_points.is_empty():
		return

	# Prefer spawn points far from the player so enemies don't pop in on
	# top of / right next to them with no time to react.
	var spawn_candidates: Array[Vector2i] = walkable_points
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var player_local_pos: Vector2 = to_local((players[0] as Node2D).global_position)
		var min_spawn_distance := 48.0  # px, ~2 grid cells

		var far_points: Array[Vector2i] = []
		for pt in walkable_points:
			var cell_center: Vector2 = Vector2(pt) * 24.0 + Vector2(12.0, 12.0)
			if cell_center.distance_to(player_local_pos) >= min_spawn_distance:
				far_points.append(pt)

		if not far_points.is_empty():
			spawn_candidates = far_points
		else:
			# Room's too small for anything to clear the distance - fall
			# back to whichever points are farthest from the player instead
			# of spawning right on top of them.
			walkable_points.sort_custom(func(a, b):
				var da: float = (Vector2(a) * 24.0 + Vector2(12.0, 12.0)).distance_to(player_local_pos)
				var db: float = (Vector2(b) * 24.0 + Vector2(12.0, 12.0)).distance_to(player_local_pos)
				return da > db
			)
			spawn_candidates = walkable_points.slice(0, mini(walkable_points.size(), 6))

	spawn_candidates.shuffle()
	var target_count: int = randi_range(enemies_per_room_min, enemies_per_room_max)
	var spawn_count: int = min(target_count, spawn_candidates.size())

	for i in range(spawn_count):
		var grid_pos: Vector2i = spawn_candidates[i]
		var spawn_position: Vector2 = Vector2(grid_pos) * 24.0 + Vector2(12.0, 12.0)
		
		var selected_scene: PackedScene = enemy_pool.pick_random()
		var enemy: Enemy = selected_scene.instantiate() as Enemy
		if enemy != null:
			enemy.position = spawn_position
			
			if enemy.has_method("set_astar_grid"):
				enemy.set_astar_grid(astar)

			enemy.died.connect(_on_enemy_died.bind(enemy))
			active_enemies += 1

			add_child(enemy)

func _build_room_interior_detector(room: PlacedRoom) -> void:
	var detector := Area2D.new()
	detector.name = "InteriorDetector"
	detector.collision_layer = 0
	detector.collision_mask = 1  # Player layer

	# Inset detector 36px from room outer edges so doors never close while player is in the threshold
	var margin := 36.0
	for cell in room.template.footprint:
		var shape := RectangleShape2D.new()
		shape.size = cell_size - Vector2(margin * 2.0, margin * 2.0)
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = Vector2(cell) * cell_size + cell_size / 2.0
		detector.add_child(collider)

	detector.body_entered.connect(_on_player_entered_interior)
	detector.body_exited.connect(_on_player_exited_interior)
	add_child(detector)

## Room locks after the player dwells inside the interior zone for
## lock_dwell_time seconds, not on first touch, so a quick doorway
## pass-through doesn't seal it behind them. See _process() for the countdown.
func _on_player_entered_interior(body: Node2D) -> void:
	if body.is_in_group("player") and not room_cleared and not room_locked:
		_dwell_timer = lock_dwell_time

func _on_player_exited_interior(body: Node2D) -> void:
	if body.is_in_group("player"):
		_dwell_timer = 0.0

func lock_room() -> void:
	room_locked = true
	# 1. Lock all doors first
	for child in door_markers.get_children():
		if child is Door:
			child.lock()

	# 2. Spawn the room's contents inside the locked arena
	if current_placed_room.room_type == RoomTemplate.RoomType.BOSS:
		_spawn_boss(current_placed_room)
	else:
		_spawn_enemies_safely(current_placed_room)

func unlock_room() -> void:
	room_locked = false
	room_cleared = true
	for child in door_markers.get_children():
		if child is Door:
			child.unlock()



func _on_enemy_died(enemy: Enemy) -> void:
	var death_pos := enemy.position
	active_enemies -= 1
	if active_enemies <= 0:
		if randf() < heart_drop_chance:
			_spawn_heart(death_pos)
		unlock_room()
