class_name ObstacleEntry
extends Resource

# Local pixel position within the room.
@export var local_position: Vector2 = Vector2.ZERO
# The obstacle scene to spawn (e.g. big_obstacle.tscn, small_obstacle.tscn).
@export var scene: PackedScene
