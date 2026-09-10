class_name WormBoss
extends Node2D

## A chain of BossSegment pieces, head to tail. Self-contained: spawns and
## positions its own segments in _ready() (room_scene_base.gd's _spawn_boss
## just positions this node and adds it as a child).
##
## Movement is not A*-pathfinding: the head travels in a straight line at
## its last picked angle, and only picks a new one (a free continuous
## angle, no fixed compass) when it hits something, biased back toward the
## player with no distance cutoff.
##
## Body segments don't move under their own physics - they read their
## position off a recorded trail of the head's past positions ("conga
## line" follow), spaced by segment_spacing. A middle/tail segment dying
## just shortens the chain; a head death promotes the next segment to head.

signal defeated

@export var segment_scene: PackedScene
@export var segment_count: int = 6
@export var segment_spacing: float = 24.0
@export var speed: float = 140.0
@export var trail_sample_distance: float = 4.0
@export var head_health: int = 5
@export var body_health: int = 3
@export var head_radius: float = 14.0
@export var body_radius: float = 10.0
@export var spawn_freeze_duration: float = 0.5

var segments: Array[BossSegment] = []
var trail: PackedVector2Array = PackedVector2Array()
var move_dir: Vector2 = Vector2.ZERO
var player: Node2D = null
var spawn_freeze_timer: float = 0.0

func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D

	spawn_freeze_timer = spawn_freeze_duration
	var initial_dir := _direction_to_player(global_position)
	move_dir = initial_dir.normalized() if initial_dir.length() > 0.001 else Vector2.RIGHT

	var spawn_pos := global_position
	var back := -move_dir

	# Pre-fill the trail behind the spawn point so followers start in place.
	trail.clear()
	var trail_len := _trail_len_needed()
	for i in range(trail_len):
		trail.append(spawn_pos + back * trail_sample_distance * float(i))

	segments.clear()
	for i in range(segment_count):
		var seg := _spawn_segment(i == 0)
		seg.global_position = spawn_pos + back * segment_spacing * float(i)
		segments.append(seg)

func _spawn_segment(is_head_flag: bool) -> BossSegment:
	var seg: BossSegment = segment_scene.instantiate() as BossSegment
	seg.is_head = is_head_flag
	seg.segment_radius = head_radius if is_head_flag else body_radius
	seg.max_health = head_health if is_head_flag else body_health
	seg.segment_died.connect(_on_segment_died)
	add_child(seg)
	return seg

func _trail_stride() -> int:
	return maxi(1, int(round(segment_spacing / trail_sample_distance)))

func _trail_len_needed() -> int:
	return segment_count * _trail_stride() + 4

func is_spawn_frozen(delta: float) -> bool:
	if spawn_freeze_timer <= 0.0:
		return false
	spawn_freeze_timer -= delta
	if not segments.is_empty():
		segments[0].velocity = Vector2.ZERO
		segments[0].move_and_slide()
	return true

func _physics_process(delta: float) -> void:
	if segments.is_empty():
		return
	if is_spawn_frozen(delta):
		return
	_move_head()
	_record_trail()
	_update_followers()

func _move_head() -> void:
	var head := segments[0]
	head.velocity = move_dir * speed
	head.move_and_slide()
	# worm_head.png faces down instead of up like the rest of the art -
	# negating the direction here corrects for it.
	head.face_direction(-move_dir)

	if head.get_slide_collision_count() > 0:
		move_dir = _choose_new_direction(head)

func _direction_to_player(from_pos: Vector2) -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.global_position - from_pos

## New heading, in priority order: straight at the player if not blocked by
## whatever the head is touching this frame; else a physical bounce off
## the contact(s); else the averaged outward normal.
func _choose_new_direction(head: BossSegment) -> Vector2:
	var normals: Array[Vector2] = []
	for i in range(head.get_slide_collision_count()):
		normals.append(head.get_slide_collision(i).get_normal())

	var to_player := _direction_to_player(head.global_position)
	if to_player.length() > 0.001:
		var preferred := to_player.normalized()
		if _clears_all(preferred, normals):
			return preferred

	var reflected := move_dir
	for n in normals:
		reflected = reflected.bounce(n)
	if reflected.length() > 0.001:
		reflected = reflected.normalized()
		if _clears_all(reflected, normals):
			return reflected

	var escape := Vector2.ZERO
	for n in normals:
		escape += n
	if escape.length() > 0.001:
		return escape.normalized()

	return -move_dir

func _clears_all(dir: Vector2, normals: Array[Vector2]) -> bool:
	for n in normals:
		if dir.dot(n) <= 0.05:
			return false
	return true

func _record_trail() -> void:
	var head_pos := segments[0].global_position
	if trail.is_empty() or head_pos.distance_to(trail[0]) >= trail_sample_distance:
		trail.insert(0, head_pos)
		var max_len := _trail_len_needed()
		if trail.size() > max_len:
			trail.resize(max_len)

func _update_followers() -> void:
	if trail.is_empty():
		return
	var stride := _trail_stride()
	for i in range(1, segments.size()):
		var trail_index: int = mini(i * stride, trail.size() - 1)
		var target: Vector2 = trail[trail_index]
		# Face direction of travel before overwriting position.
		segments[i].face_direction(target - segments[i].global_position)
		segments[i].global_position = target

func _on_segment_died(segment: BossSegment) -> void:
	var idx := segments.find(segment)
	if idx == -1:
		return

	var was_head := idx == 0
	segments.remove_at(idx)

	if segments.is_empty():
		defeated.emit()
		queue_free()
		return

	if was_head:
		_promote_head(segments[0])

func _promote_head(new_head: BossSegment) -> void:
	new_head.is_head = true
	new_head.segment_radius = head_radius
	new_head.refresh_visual()
	# Restart the trail from the new head's position (followers briefly
	# bunch up and re-stretch as it regrows).
	trail.clear()
	trail.append(new_head.global_position)
