class_name BossGuardMinion
extends Enemy

## The "defend" half of HiveQueenBoss's two minion types. Extends Enemy for
## its health/take_damage/died/spawn-freeze fields, but overrides
## _physics_process entirely: holds a slot in a slowly rotating ring around
## the boss instead of chasing. The "shield" is purely physical/positional
## - a normal, independently killable enemy - not a damage-immunity flag.

@export var move_speed: float = 90.0
@export var orbit_radius: float = 32.0
@export var orbit_speed: float = 1.0  # radians/sec the whole ring rotates at

var boss: Node2D = null
var orbit_phase: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group("boss_guards")

func _physics_process(delta: float) -> void:
	if player == null:
		return

	if is_spawn_frozen(delta):
		return

	orbit_phase += orbit_speed * delta
	_seek_orbit_slot(delta)
	_check_player_contact(delta)

## Adapts Enemy._get_surround_offset()'s angular-slot trick to orbit the
## boss instead of the player. Peers are scoped to guards sharing the same boss.
func _seek_orbit_slot(_delta: float) -> void:
	var target := global_position

	if boss != null and is_instance_valid(boss):
		var peers: Array = []
		for node in get_tree().get_nodes_in_group("boss_guards"):
			if node is BossGuardMinion and (node as BossGuardMinion).boss == boss:
				peers.append(node)

		peers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
		var index := peers.find(self)
		var slot_count := maxi(1, peers.size())
		var angle := orbit_phase + (TAU / float(slot_count)) * float(maxi(index, 0))
		target = boss.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius

	var to_target := target - global_position
	if to_target.length() > 2.0:
		velocity = to_target.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	SpriteFacing.apply(visual, velocity)

## Same attack_timer-gated contact damage as Enemy._perform_melee_attack(),
## applied unconditionally each tick (there's no chase/attack state here).
func _check_player_contact(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta

	if attack_timer <= 0.0 and global_position.distance_to(player.global_position) <= attack_range:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)
		attack_timer = attack_cooldown
