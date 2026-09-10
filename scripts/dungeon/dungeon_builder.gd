class_name DungeonBuilder
extends Node2D

## Instances a generated Array[PlacedRoom] into the tree, positioned in
## world space. Attach to a Node2D that will be the parent of all rooms.

## Pixels per grid cell - must match the room scenes' cell size.
@export var cell_size: Vector2 = Vector2(320, 180)

const FLOOR_TILE_SET: TileSet = preload("res://assets/tiles/floors/floor_tileset.tres")

var placed_rooms: Array[PlacedRoom] = []
var room_nodes: Dictionary = {}  # room id (int) -> instanced room Node


func build(rooms: Array[PlacedRoom]) -> void:
	placed_rooms = rooms
	for room in rooms:
		_instance_room(room)


func _instance_room(room: PlacedRoom) -> void:
	var instance := room.template.scene.instantiate()
	add_child(instance)

	instance.position = Vector2(room.origin) * cell_size
	room_nodes[room.id] = instance

	# Room scenes using room_scene_base.gd generate their own floor/walls
	# inside setup_room() - see room_scene_base.gd and room_auto_builder.gd.
	if instance.has_method("setup_room"):
		instance.setup_room(room, FLOOR_TILE_SET)


func get_room_node(room_id: int) -> Node:
	return room_nodes.get(room_id)


func clear() -> void:
	for child in get_children():
		child.queue_free()
	room_nodes.clear()
	placed_rooms.clear()
