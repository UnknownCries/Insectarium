class_name DoorSlot
extends Resource

## A single door slot definition, local to a RoomTemplate. Top-level (not
## nested in RoomTemplate) because Godot's Inspector "New Resource" picker
## doesn't reliably list inner classes.

enum Direction {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

## Local footprint cell this door is attached to (usually (0,0)).
@export var cell: Vector2i = Vector2i.ZERO

## Which side of that cell the door faces.
@export var direction: Direction = Direction.NORTH
