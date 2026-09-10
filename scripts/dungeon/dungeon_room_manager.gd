class_name DungeonRoomManager
extends Node2D

## Coordinates room-to-room transitions: tracks which room's bounds the
## player's position currently falls inside, and clamps the camera to that
## room's bounds so it never reveals neighboring rooms.

signal room_changed(new_room_id: int, previous_room_id: int)

@export var builder: DungeonBuilder
@export var camera: Camera2D
@export var cell_size: Vector2 = Vector2(320, 180)

var current_room_id: int = -1
var _player: Node2D
var _generator_rooms: Array[PlacedRoom] = []  # set via setup(), gives us world_door_slots/occupied_cells per room
var _room_lookup: Dictionary = {}  # room id -> PlacedRoom, for quick bounds lookups


func setup(rooms: Array[PlacedRoom], start_room_id: int) -> void:
	_generator_rooms = rooms
	_room_lookup.clear()
	for r in rooms:
		_room_lookup[r.id] = r

	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		push_error("DungeonRoomManager: no node in group 'player' found. Add the player to the 'player' group.")

	_enter_room(start_room_id, true)


func _process(_delta: float) -> void:
	if camera and _player and current_room_id != -1:
		_update_current_room()
		_update_camera()


func _world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))


## Which room "contains" the player is checked fresh every frame from a
## continuous fact of their position, not an event. Uses exact cell
## membership (room.occupied_cells), not a bounding-box test - an irregular
## footprint (L/T-shaped) can have a "missing corner" cell that actually
## belongs to a different room.
func _update_current_room() -> void:
	var player_cell := _world_to_cell(_player.global_position)

	if _room_lookup.has(current_room_id):
		var room: PlacedRoom = _room_lookup[current_room_id]
		if room.occupied_cells.has(player_cell):
			return

	for id in _room_lookup:
		var room: PlacedRoom = _room_lookup[id]
		if room.occupied_cells.has(player_cell):
			if id != current_room_id:
				var previous_id := current_room_id
				current_room_id = id
				_update_room_visibility()
				room_changed.emit(id, previous_id)
			return


func _enter_room(room_id: int, is_initial: bool) -> void:
	var previous_id := current_room_id
	current_room_id = room_id
	_update_room_visibility()
	if not is_initial:
		room_changed.emit(room_id, previous_id)


## Only the room the player is in is ever rendered - every other room is
## hidden outright (CanvasItem visibility cascades to the whole subtree).
## This is what stops a neighboring room from leaking through an irregular
## room's "missing corner" cell.
func _update_room_visibility() -> void:
	if builder == null:
		return
	for id in _room_lookup:
		var node := builder.get_room_node(id)
		if node != null:
			node.visible = (id == current_room_id)


## Updates the camera's position, clamped to the current room's world-space
## bounding box, so it follows the player within the room but never shows
## past its edges (Isaac-style fixed zoom, room-locked camera).
func _update_camera() -> void:
	if not _room_lookup.has(current_room_id):
		return
	var room: PlacedRoom = _room_lookup[current_room_id]
	var bounds := _room_world_bounds(room)

	# Clamp the camera's center within [bounds.min + half_extent, bounds.max
	# - half_extent] so the viewport itself never shows outside room bounds.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_extent: Vector2 = (viewport_size / camera.zoom) / 2.0

	var min_center: Vector2 = bounds.position + half_extent
	var max_center: Vector2 = bounds.position + bounds.size - half_extent

	# If the room is smaller than the viewport on an axis, min > max - just
	# center the camera on that axis instead of clamping.
	var target: Vector2 = _player.global_position
	var cam_pos := Vector2.ZERO

	if min_center.x <= max_center.x:
		cam_pos.x = clamp(target.x, min_center.x, max_center.x)
	else:
		cam_pos.x = bounds.position.x + bounds.size.x / 2.0

	if min_center.y <= max_center.y:
		cam_pos.y = clamp(target.y, min_center.y, max_center.y)
	else:
		cam_pos.y = bounds.position.y + bounds.size.y / 2.0

	camera.global_position = cam_pos


## Returns the world-space Rect2 bounding box of a room (top-left position
## + size), computed from its occupied grid cells.
func _room_world_bounds(room: PlacedRoom) -> Rect2:
	var min_cell := room.occupied_cells[0]
	var max_cell := room.occupied_cells[0]
	for cell in room.occupied_cells:
		min_cell.x = min(min_cell.x, cell.x)
		min_cell.y = min(min_cell.y, cell.y)
		max_cell.x = max(max_cell.x, cell.x)
		max_cell.y = max(max_cell.y, cell.y)

	var top_left: Vector2 = Vector2(min_cell) * cell_size
	var size: Vector2 = Vector2(max_cell - min_cell + Vector2i.ONE) * cell_size
	return Rect2(top_left, size)
