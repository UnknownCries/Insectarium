class_name RoomAutoBuilder
extends RefCounted

## Generates floor tiles and wall segments (ColorRect + StaticBody2D/
## CollisionShape2D) for a room automatically, based on its footprint and
## door slots. Called from a room scene's setup_room() - see room_scene_base.gd.

const WALL_THICKNESS := 16.0
const WALL_COLOR := Color(0.55, 0.8, 0.95, 0.8)  # glass-blue enclosure
const DOOR_WIDTH := 64.0  # Pixel width/height of the door frame

## Floor tiles only - walls stay plain ColorRect (no art for them). Each
## floor PNG is 32x18, dividing cell_size (320x180) into an exact 10x10 grid.
const FLOOR_TILE_SIZE := Vector2(32.0, 18.0)
const FLOOR_TILE_VARIANT_COUNT := 5  # matches floor_tileset.tres's registered source count - update this when adding more tile variants there

## Stamps a random one of the tile_set's FLOOR_TILE_VARIANT_COUNT sources at
## every 32x18 position covering the rectangle [origin, origin+size).
static func _fill_floor_tiles(tilemap: TileMap, origin: Vector2, size: Vector2) -> void:
	var cols := int(round(size.x / FLOOR_TILE_SIZE.x))
	var rows := int(round(size.y / FLOOR_TILE_SIZE.y))
	var origin_cell := Vector2i(roundi(origin.x / FLOOR_TILE_SIZE.x), roundi(origin.y / FLOOR_TILE_SIZE.y))
	for x in range(cols):
		for y in range(rows):
			var source_id := randi() % FLOOR_TILE_VARIANT_COUNT
			tilemap.set_cell(0, origin_cell + Vector2i(x, y), source_id, Vector2i(0, 0))

static func spawn_obstacles(obstacles_parent: Node2D, template: RoomTemplate, _cell_size: Vector2) -> void:
	# Clear out any leftover placeholders in the scene
	for child in obstacles_parent.get_children():
		child.queue_free()

	if template == null or template.obstacles.is_empty():
		return

	for entry in template.obstacles:
		if entry == null or entry.scene == null:
			continue

		var instance := entry.scene.instantiate() as Node2D
		if instance == null:
			continue

		instance.position = entry.local_position
		obstacles_parent.add_child(instance)

static func _build_wall_with_door(
	walls_body: StaticBody2D,
	walls_visual_parent: Node2D,
	door_markers_parent: Node2D,
	cell: Vector2i,
	dir: DoorSlot.Direction,
	cell_size: Vector2,
	target_room_id: int
) -> void:
	var cell_origin := Vector2(cell) * cell_size
	var is_horizontal := (dir == DoorSlot.Direction.NORTH or dir == DoorSlot.Direction.SOUTH)
	var wall_length := cell_size.x if is_horizontal else cell_size.y

	var door_center_ratio := 0.5
	var door_center_pos := wall_length * door_center_ratio
	var door_start := clampf(door_center_pos - (DOOR_WIDTH / 2.0), WALL_THICKNESS, wall_length - DOOR_WIDTH - WALL_THICKNESS)
	var door_end := door_start + DOOR_WIDTH

	if door_start > 0:
		_build_partial_wall(walls_body, walls_visual_parent, cell_origin, dir, 0.0, door_start, cell_size)

	if door_end < wall_length:
		_build_partial_wall(walls_body, walls_visual_parent, cell_origin, dir, door_end, wall_length, cell_size)

	var door_size: Vector2
	var door_pos: Vector2
	match dir:
		DoorSlot.Direction.NORTH:
			door_size = Vector2(DOOR_WIDTH, WALL_THICKNESS)
			door_pos = cell_origin + Vector2(door_start + DOOR_WIDTH / 2.0, 0)
		DoorSlot.Direction.SOUTH:
			door_size = Vector2(DOOR_WIDTH, WALL_THICKNESS)
			door_pos = cell_origin + Vector2(door_start + DOOR_WIDTH / 2.0, cell_size.y)
		DoorSlot.Direction.EAST:
			door_size = Vector2(WALL_THICKNESS, DOOR_WIDTH)
			door_pos = cell_origin + Vector2(cell_size.x, door_start + DOOR_WIDTH / 2.0)
		DoorSlot.Direction.WEST:
			door_size = Vector2(WALL_THICKNESS, DOOR_WIDTH)
			door_pos = cell_origin + Vector2(0, door_start + DOOR_WIDTH / 2.0)

	var door := Door.new()
	door.name = "DoorBlock_%d_%d_%d" % [cell.x, cell.y, dir]
	door.add_to_group("room_doors")

	var door_visual := ColorRect.new()
	door_visual.name = "ColorRect"
	door_visual.color = Color(0.45, 0.3, 0.15)  # wood-brown when locked
	door_visual.size = door_size
	door_visual.position = -door_size / 2.0
	door.add_child(door_visual)

	var door_shape := RectangleShape2D.new()
	door_shape.size = door_size
	var door_collider := CollisionShape2D.new()
	door_collider.name = "CollisionShape2D"
	door_collider.shape = door_shape
	door.add_child(door_collider)

	door.position = door_pos
	door_markers_parent.add_child(door)
	door.unlock()  # Start unlocked

	_build_door_trigger_at_offset(door_markers_parent, cell_origin, dir, door_start, DOOR_WIDTH, target_room_id, cell, cell_size)

static func _build_partial_wall(
	walls_body: StaticBody2D,
	walls_visual_parent: Node2D,
	cell_origin: Vector2,
	dir: DoorSlot.Direction,
	start_pos: float,
	end_pos: float,
	cell_size: Vector2
) -> void:
	var length := end_pos - start_pos
	var seg_size: Vector2
	var seg_center: Vector2
	match dir:
		DoorSlot.Direction.NORTH:
			seg_size = Vector2(length, WALL_THICKNESS)
			seg_center = cell_origin + Vector2(start_pos + length / 2.0, 0)
		DoorSlot.Direction.SOUTH:
			seg_size = Vector2(length, WALL_THICKNESS)
			seg_center = cell_origin + Vector2(start_pos + length / 2.0, cell_size.y)
		DoorSlot.Direction.EAST:
			seg_size = Vector2(WALL_THICKNESS, length)
			seg_center = cell_origin + Vector2(cell_size.x, start_pos + length / 2.0)
		DoorSlot.Direction.WEST:
			seg_size = Vector2(WALL_THICKNESS, length)
			seg_center = cell_origin + Vector2(0, start_pos + length / 2.0)

	var visual := ColorRect.new()
	visual.color = WALL_COLOR
	visual.size = seg_size
	visual.position = seg_center - seg_size / 2.0
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	walls_visual_parent.add_child(visual)

	var shape := RectangleShape2D.new()
	shape.size = seg_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = seg_center
	walls_body.add_child(collider)


static func _build_door_trigger_at_offset(
	door_markers_parent: Node2D,
	cell_origin: Vector2,
	dir: DoorSlot.Direction,
	gap_start: float,
	gap_width: float,
	target_room_id: int,
	cell: Vector2i,
	cell_size: Vector2
) -> void:
	var trigger_size: Vector2
	var trigger_center: Vector2

	# Inset width by 12px on each side so touching wall corners doesn't trigger
	var inset := 12.0
	var active_gap := maxf(8.0, gap_width - (inset * 2.0))
	var active_start := gap_start + inset
	var thickness := 8.0  # Thin depth placed right inside the threshold

	match dir:
		DoorSlot.Direction.NORTH:
			trigger_size = Vector2(active_gap, thickness)
			trigger_center = cell_origin + Vector2(active_start + active_gap / 2.0, thickness / 2.0)
		DoorSlot.Direction.SOUTH:
			trigger_size = Vector2(active_gap, thickness)
			trigger_center = cell_origin + Vector2(active_start + active_gap / 2.0, cell_size.y - thickness / 2.0)
		DoorSlot.Direction.EAST:
			trigger_size = Vector2(thickness, active_gap)
			trigger_center = cell_origin + Vector2(cell_size.x - thickness / 2.0, active_start + active_gap / 2.0)
		DoorSlot.Direction.WEST:
			trigger_size = Vector2(thickness, active_gap)
			trigger_center = cell_origin + Vector2(thickness / 2.0, active_start + active_gap / 2.0)

	var area := Area2D.new()
	area.name = "DoorTrigger_%d_%d_%d" % [cell.x, cell.y, dir]
	area.collision_layer = 0
	area.collision_mask = 1
	area.add_to_group("door_trigger")

	area.set_meta("target_room_id", target_room_id)
	area.set_meta("direction", dir)

	var shape := RectangleShape2D.new()
	shape.size = trigger_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	area.add_child(collider)
	area.position = trigger_center

	door_markers_parent.add_child(area)


## Builds floor + walls under the given parent nodes, from room's
## footprint/door state. tile_set draws floor as a randomized TileMap;
## null falls back to plain ColorRect cells. Walls always stay ColorRect.
static func build(
	floor_parent: Node2D,
	walls_body: StaticBody2D,
	walls_visual_parent: Node2D,
	door_markers_parent: Node2D,
	obstacles_parent: Node2D,
	room: PlacedRoom,
	cell_size: Vector2,
	tile_set: TileSet = null
) -> void:
	var footprint: Array[Vector2i] = room.template.footprint
	var door_slots: Array[DoorSlot] = room.template.door_slots

	var footprint_set := {}
	for cell in footprint:
		footprint_set[cell] = true

	# Lookup of (cell, direction) pairs that are actually connected doors
	# (leave a gap) vs. declared-but-unconnected slots (still get a wall).
	# Index i in door_slots corresponds to index i in room.world_door_slots
	# (see placed_room.gd _init()).
	var door_lookup := {}       # key -> true (used by wall-skip loop)
	var door_destinations := {} # key -> other room id (used to build door triggers)
	for i in door_slots.size():
		if i < room.world_door_slots.size() and room.world_door_slots[i]["connected_to"] != -1:
			var local_slot: DoorSlot = door_slots[i]
			var key := _slot_key(local_slot.cell, local_slot.direction)
			door_lookup[key] = true
			door_destinations[key] = room.world_door_slots[i]["connected_to"]

	# --- Floor: tiled from tile_set if given, else one ColorRect per cell ---
	if tile_set != null:
		var floor_tilemap := TileMap.new()
		floor_tilemap.name = "FloorTiles"
		floor_tilemap.tile_set = tile_set
		floor_parent.add_child(floor_tilemap)
		for cell in footprint:
			_fill_floor_tiles(floor_tilemap, Vector2(cell) * cell_size, cell_size)
	else:
		for cell in footprint:
			var floor_rect := ColorRect.new()
			floor_rect.color = Color(0.4, 0.4, 0.4)  # placeholder gray, no floor art fallback
			floor_rect.position = Vector2(cell) * cell_size
			floor_rect.size = cell_size
			floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			floor_rect.name = "FloorCell_%d_%d" % [cell.x, cell.y]
			floor_parent.add_child(floor_rect)

	# --- Walls: one segment per outer edge of the footprint ---
	for cell in footprint:
		for dir in [DoorSlot.Direction.NORTH, DoorSlot.Direction.EAST, DoorSlot.Direction.SOUTH, DoorSlot.Direction.WEST]:
			var neighbor: Vector2i = cell + RoomTemplate.direction_to_vector(dir)
			if footprint_set.has(neighbor):
				continue  # interior edge, skip

			var key := _slot_key(cell, dir)
			if door_lookup.has(key):
				var target_room_id: int = door_destinations[key]
				_build_wall_with_door(walls_body, walls_visual_parent, door_markers_parent, cell, dir, cell_size, target_room_id)
			else:
				_build_wall_segment(walls_body, walls_visual_parent, cell, dir, cell_size)

	# --- Spawn Data-Driven Obstacles ---
	if obstacles_parent != null:
		spawn_obstacles(obstacles_parent, room.template, cell_size)

static func _slot_key(cell: Vector2i, dir: DoorSlot.Direction) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, dir]


static func _build_wall_segment(
	walls_body: StaticBody2D,
	walls_visual_parent: Node2D,
	cell: Vector2i,
	dir: DoorSlot.Direction,
	cell_size: Vector2
) -> void:
	var cell_origin: Vector2 = Vector2(cell) * cell_size  # top-left of this cell, local space

	var seg_size: Vector2
	var seg_center: Vector2  # center position, local to room, for CollisionShape2D

	match dir:
		DoorSlot.Direction.NORTH:
			seg_size = Vector2(cell_size.x, WALL_THICKNESS)
			seg_center = cell_origin + Vector2(cell_size.x / 2.0, 0)
		DoorSlot.Direction.SOUTH:
			seg_size = Vector2(cell_size.x, WALL_THICKNESS)
			seg_center = cell_origin + Vector2(cell_size.x / 2.0, cell_size.y)
		DoorSlot.Direction.EAST:
			seg_size = Vector2(WALL_THICKNESS, cell_size.y)
			seg_center = cell_origin + Vector2(cell_size.x, cell_size.y / 2.0)
		DoorSlot.Direction.WEST:
			seg_size = Vector2(WALL_THICKNESS, cell_size.y)
			seg_center = cell_origin + Vector2(0, cell_size.y / 2.0)

	var visual := ColorRect.new()  # uses top-left position, not center
	visual.color = WALL_COLOR
	visual.size = seg_size
	visual.position = seg_center - seg_size / 2.0
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.name = "WallVisual_%d_%d_%d" % [cell.x, cell.y, dir]
	walls_visual_parent.add_child(visual)

	var shape := RectangleShape2D.new()  # CollisionShape2D uses center position
	shape.size = seg_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = seg_center
	collider.name = "WallCollision_%d_%d_%d" % [cell.x, cell.y, dir]
	walls_body.add_child(collider)
