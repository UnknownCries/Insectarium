class_name RangedEnemy
extends Enemy

@export var bullet_scene: PackedScene
@export var stop_distance: float = 140.0
@export var fire_rate: float = 0.5
@export var flee_distance: float = 100.0

@onready var los_raycast: RayCast2D = $RayCast2D

var shoot_cooldown_timer: float = 0.0

func _ready() -> void:
	super._ready()
	if attack_range <= stop_distance:
		attack_range = stop_distance + 20.0

	if los_raycast != null:
		los_raycast.add_exception(self)

func _physics_process(delta: float) -> void:
	if player == null:
		return

	if is_spawn_frozen(delta):
		return

	if shoot_cooldown_timer > 0.0:
		shoot_cooldown_timer -= delta

	var dist_to_player := global_position.distance_to(player.global_position)

	if dist_to_player <= attack_range and has_line_of_sight():
		if dist_to_player < flee_distance:
			var flee_dir := (global_position - player.global_position).normalized()
			velocity = flee_dir * speed
			move_and_slide()
		elif dist_to_player > stop_distance:
			var approach_dir := (player.global_position - global_position).normalized()
			velocity = approach_dir * speed
			move_and_slide()
		else:
			velocity = Vector2.ZERO

		if shoot_cooldown_timer <= 0.0:
			_shoot()
			shoot_cooldown_timer = fire_rate

		# Face wherever it's actually moving (flee/approach); once planted and
		# just holding position, face the player it's shooting at instead.
		var facing_dir := velocity if velocity.length() > 0.01 else (player.global_position - global_position)
		SpriteFacing.apply(visual, facing_dir)
	else:
		current_state = State.CHASE
		var actual_range = attack_range
		attack_range = 0.0
		super._physics_process(delta)
		attack_range = actual_range

func has_line_of_sight() -> bool:
	if los_raycast == null:
		return false
	los_raycast.target_position = los_raycast.to_local(player.global_position)
	los_raycast.force_raycast_update()
	return not los_raycast.is_colliding()

func _shoot() -> void:
	if bullet_scene == null:
		return

	var bullet = bullet_scene.instantiate()

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = global_position

	var dir := (player.global_position - global_position).normalized()
	if bullet.has_method("setup"):
		bullet.setup(dir, self)
