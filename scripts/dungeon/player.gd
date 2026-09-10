class_name Player
extends CharacterBody2D

## Player character. Must stay in the "player" group with a CollisionShape2D
## - other systems depend on both for collision and lookup.

signal health_changed(current: int, max: int)
signal died

@export var max_health: int = 10
@export var speed: float = 100.0
@export var bullet_scene: PackedScene
@export var damage: int = 1
@export var fire_rate: float = 0.5  # Time in seconds between shots (smaller = faster)
@export var attack_range: float = 150.0  # Max distance a shot travels before disappearing (rooms are ~320x180)
@export var invincibility_duration: float = 0.5  # untouchable window after any hit
@export var flicker_interval: float = 0.08       # visual blink rate while invincible

@onready var visual: Sprite2D = $Visual
@onready var shoot_sound: AudioStreamPlayer = $ShootSound

var health: int
var fire_timer: float = 0.0
var is_dead: bool = false
var invincible_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	health = max_health

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if invincible_timer > 0.0:
		invincible_timer -= delta
		if invincible_timer <= 0.0:
			invincible_timer = 0.0
			visual.visible = true
		else:
			# Isaac-style blink while untouchable, purely visual.
			visual.visible = int(invincible_timer / flicker_interval) % 2 == 0

	# Reads WASD / Arrow input and normalizes diagonal movement automatically
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction * speed
	move_and_slide()

	SpriteFacing.apply(visual, get_global_mouse_position() - global_position)

	if fire_timer > 0.0:
		fire_timer -= delta

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_timer <= 0.0:
		shoot()
		fire_timer = fire_rate

func shoot() -> void:
	if bullet_scene == null:
		return

	var bullet_instance := bullet_scene.instantiate() as Bullet
	if bullet_instance == null:
		return

	bullet_instance.global_position = global_position
	bullet_instance.setup((get_global_mouse_position() - global_position).normalized(), self)
	bullet_instance.damage = damage
	bullet_instance.max_distance = attack_range
	get_tree().current_scene.add_child(bullet_instance)

	shoot_sound.play()

func take_damage(amount: int) -> void:
	if is_dead or invincible_timer > 0.0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		is_dead = true
		velocity = Vector2.ZERO
		died.emit()
	else:
		invincible_timer = invincibility_duration

func heal(amount: int) -> void:
	if is_dead:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)
