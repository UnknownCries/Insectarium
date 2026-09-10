class_name RoomTemplate
extends Resource

## A "blueprint" for a room: what cells it occupies on the grid, where its
## doors are, and which scene to instance for its actual contents.
##
## One .tres resource per room design. No runtime rotation - each distinct
## shape/orientation is its own separate template (e.g. an L-room facing a
## different corner is a second .tres with a different footprint/door_slots).

@export var obstacles: Array[ObstacleEntry] = []

enum RoomType {
	START,
	NORMAL,
	BOSS,
	ITEM,
}

## Local grid cells this room occupies, relative to (0,0).
## Example L-shape (notch bottom-right): [(0,0), (1,0), (0,1)]
## Example 1x1:      [(0,0)]
## Example 2x2:       [(0,0), (1,0), (0,1), (1,1)]
## Example vertical 2x1: [(0,0), (0,1)]
@export var footprint: Array[Vector2i] = [Vector2i.ZERO]

## Door slots. Each entry describes a door on the EDGE of one of the
## footprint cells. See door_slot.gd.
@export var door_slots: Array[DoorSlot] = []

## The actual room scene: walls, floor art, pre-placed obstacles, and
## Marker2D nodes matching each door_slot (see room scene instructions).
@export var scene: PackedScene

@export var room_type: RoomType = RoomType.NORMAL

## Higher weight = more likely to be picked when multiple templates
## could fit a given slot.
@export var weight: float = 1.0

## Optional tag list for filtering (e.g. ["small"], ["has_water"]) if you
## want finer control later. Not required to get started.
@export var tags: Array[String] = []


## Utility: opposite direction (used constantly when matching doors)
static func opposite_direction(dir: DoorSlot.Direction) -> DoorSlot.Direction:
	return ((dir + 2) % 4) as DoorSlot.Direction


## Utility: direction to grid offset vector
static func direction_to_vector(dir: DoorSlot.Direction) -> Vector2i:
	match dir:
		DoorSlot.Direction.NORTH: return Vector2i(0, -1)
		DoorSlot.Direction.EAST: return Vector2i(1, 0)
		DoorSlot.Direction.SOUTH: return Vector2i(0, 1)
		DoorSlot.Direction.WEST: return Vector2i(-1, 0)
	return Vector2i.ZERO
