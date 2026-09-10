class_name PlacedRoom
extends RefCounted

## Runtime record of a room template placed on the world grid.
## Not a Resource - only exists during/after generation, held in memory.

var template: RoomTemplate
var origin: Vector2i          # world-grid position this room is anchored at
var id: int                   # unique id, assigned by the generator

# The room's assigned type for THIS instance. Defaults to the template's
# type but can be overridden (e.g. a normal room re-flagged as BOSS)
# without mutating the shared template resource.
var room_type: RoomTemplate.RoomType

# World-space occupied cells (footprint offset by origin)
var occupied_cells: Array[Vector2i] = []

# World-space door slots: each dict has "cell" (world cell), "direction",
# and "connected_to" (id of the room on the other side, or -1 if open/sealed)
var world_door_slots: Array[Dictionary] = []


func _init(p_template: RoomTemplate, p_origin: Vector2i, p_id: int) -> void:
	template = p_template
	origin = p_origin
	id = p_id
	room_type = p_template.room_type

	for local_cell in template.footprint:
		occupied_cells.append(local_cell + origin)

	for slot in template.door_slots:
		world_door_slots.append({
			"cell": slot.cell + origin,
			"direction": slot.direction,
			"connected_to": -1,
		})


## Marks the door slot at the given world cell/direction as connected to
## another room's id. Returns true if a matching slot was found.
func connect_door(world_cell: Vector2i, direction: DoorSlot.Direction, other_id: int) -> bool:
	for slot in world_door_slots:
		if slot["cell"] == world_cell and slot["direction"] == direction:
			slot["connected_to"] = other_id
			return true
	return false


## Returns all door slots that are not yet connected to anything.
func get_open_door_slots() -> Array[Dictionary]:
	return world_door_slots.filter(func(s): return s["connected_to"] == -1)
