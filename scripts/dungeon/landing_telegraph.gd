class_name LandingTelegraph
extends Node2D

## Lightweight, boss-agnostic warning indicator: grows a filled circle from
## 0 up to max_radius over a duration, marking the spot an airborne attacker
## (currently just FleaBoss) is about to reappear on top of. Purely visual -
## no collision, no gameplay logic of its own - and expects whoever spawned
## it to queue_free() it once the real landing happens (start() alone
## doesn't remove it; it just drives how fast the circle fills in).

@export var max_radius: float = 16.0
@export var color: Color = Color(0.7, 0.1, 0.1, 0.5)

var _duration: float = 1.0
var _elapsed: float = 0.0

@onready var indicator: ColorRect = $Indicator

func _ready() -> void:
	_refresh_size()

## Called by the spawner right after add_child(): how long the grow
## animation should take. Spawners pass their own airborne duration so the
## indicator finishes growing to full size exactly when the real landing
## happens.
func start(duration: float) -> void:
	_duration = maxf(duration, 0.01)
	_elapsed = 0.0

func _process(delta: float) -> void:
	if _elapsed >= _duration:
		return
	_elapsed = minf(_elapsed + delta, _duration)
	_refresh_size()

func _refresh_size() -> void:
	var t := _elapsed / _duration
	var radius := max_radius * t
	indicator.offset_left = -radius
	indicator.offset_top = -radius
	indicator.offset_right = radius
	indicator.offset_bottom = radius
	indicator.color = color
