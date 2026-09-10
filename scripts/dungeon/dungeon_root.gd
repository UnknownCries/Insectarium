extends Node2D

## Main scene root: wires dungeon generation, the player, HUD, menus, and
## floor transitions together.

@export var start_templates: Array[RoomTemplate] = []
@export var normal_templates: Array[RoomTemplate] = []
@export var empty_room_template: RoomTemplate  # drag in 1x1_room_empty.tres - used for the guaranteed boss/item dead ends
@export var target_room_count: int = 10
@export var cell_size: Vector2 = Vector2(320, 180)
@export var player_scene: PackedScene  # drag in player.tscn (built from player.gd)
@export var camera_zoom: Vector2 = Vector2(1, 1)
@export var hud_scene: PackedScene  # drag in hud.tscn (built from hud.gd)
@export var menu_overlay_scene: PackedScene  # drag in menu_overlay.tscn (built from menu_overlay.gd)
@export var loading_overlay_scene: PackedScene  # drag in loading_overlay.tscn (built from loading_overlay.gd)
@export var loading_screen_duration: float = 3.0
@export var max_floors: int = 3
@export var rooms_per_floor_increment: int = 3

@onready var builder: DungeonBuilder = $DungeonBuilder  # a child Node2D with dungeon_builder.gd attached
@onready var room_manager: DungeonRoomManager = $DungeonRoomManager  # a child Node2D with dungeon_room_manager.gd attached

var _player: Node2D
var _camera: Camera2D
# Deliberately untyped - lets .configure()/.primary_pressed/etc resolve via
# runtime duck typing instead of a static MenuOverlay/CanvasLayer type.
var _start_menu
var _game_over_menu
var _pause_menu
var _win_menu
var _loading_overlay

var current_floor: int = 1
var used_boss_scenes: Array[PackedScene] = []


func _ready() -> void:
	# Stays ALWAYS so Esc still works while paused; gameplay subtree is
	# pinned back to PAUSABLE so it actually pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	builder.process_mode = Node.PROCESS_MODE_PAUSABLE
	room_manager.process_mode = Node.PROCESS_MODE_PAUSABLE

	if hud_scene != null:
		add_child(hud_scene.instantiate())

	if menu_overlay_scene != null:
		# add_child() first - configure() touches @onready children that
		# only exist once this node is in the tree.
		_start_menu = menu_overlay_scene.instantiate()
		add_child(_start_menu)
		_start_menu.configure("INSECTARIUM", "Start", "Quit", Color(0, 0, 0, 1))
		_start_menu.primary_pressed.connect(_on_start_pressed)
		_start_menu.secondary_pressed.connect(_on_quit_pressed)
		_start_menu.show()

		_game_over_menu = menu_overlay_scene.instantiate()
		add_child(_game_over_menu)
		_game_over_menu.configure("GAME OVER", "Try Again", "Quit")
		_game_over_menu.primary_pressed.connect(_on_restart_pressed)
		_game_over_menu.secondary_pressed.connect(_on_quit_pressed)

		_pause_menu = menu_overlay_scene.instantiate()
		add_child(_pause_menu)
		_pause_menu.configure("PAUSED", "Restart", "Quit")
		_pause_menu.primary_pressed.connect(_on_restart_pressed)
		_pause_menu.secondary_pressed.connect(_on_quit_pressed)

		_win_menu = menu_overlay_scene.instantiate()
		add_child(_win_menu)
		_win_menu.configure("YOU WIN", "Play Again", "Quit")
		_win_menu.primary_pressed.connect(_on_restart_pressed)
		_win_menu.secondary_pressed.connect(_on_quit_pressed)

	if loading_overlay_scene != null:
		_loading_overlay = loading_overlay_scene.instantiate()
		add_child(_loading_overlay)
		_loading_overlay.hide()


func _unhandled_input(event: InputEvent) -> void:
	if _start_menu != null and _start_menu.visible:
		return
	if _game_over_menu != null and _game_over_menu.visible:
		return
	if _win_menu != null and _win_menu.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = not get_tree().paused
		if _pause_menu != null:
			_pause_menu.visible = get_tree().paused


func _on_start_pressed() -> void:
	if _start_menu != null:
		_start_menu.hide()
	generate_new_dungeon()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	if _game_over_menu != null:
		_game_over_menu.hide()
	if _pause_menu != null:
		_pause_menu.hide()
	if _win_menu != null:
		_win_menu.hide()
	generate_new_dungeon()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_player_died() -> void:
	get_tree().paused = true
	if _game_over_menu != null:
		_game_over_menu.show()


## Full restart: fresh run from floor 1, fresh player, every boss available again.
func generate_new_dungeon() -> void:
	current_floor = 1
	used_boss_scenes.clear()
	_rebuild_dungeon(false)


## Advances current_floor and rebuilds the dungeon, or shows the win screen
## if max_floors was already reached.
func advance_to_next_floor() -> void:
	if current_floor >= max_floors:
		get_tree().paused = true
		if _win_menu != null:
			_win_menu.show()
		return

	current_floor += 1
	await _rebuild_with_loading_screen(true)


## Shows the loading overlay for loading_screen_duration seconds, rebuilds
## behind it, then hides it - purely cosmetic pacing.
func _rebuild_with_loading_screen(preserve_player: bool) -> void:
	if _loading_overlay != null and _loading_overlay.has_method("show_for_floor"):
		_loading_overlay.show_for_floor(current_floor)

	await get_tree().create_timer(loading_screen_duration).timeout

	_rebuild_dungeon(preserve_player)

	if _loading_overlay != null:
		_loading_overlay.hide()


func get_used_boss_scenes() -> Array[PackedScene]:
	return used_boss_scenes


func mark_boss_used(scene: PackedScene) -> void:
	if scene != null and not used_boss_scenes.has(scene):
		used_boss_scenes.append(scene)


## Shared teardown-and-rebuild for generate_new_dungeon() and
## advance_to_next_floor(). preserve_player keeps the existing player node
## instead of recreating it - see _spawn_player_and_camera().
func _rebuild_dungeon(preserve_player: bool) -> void:
	# Bullets are parented to this node, not builder, so builder.clear()
	# below never touches an in-flight shot from the previous run.
	for bullet in get_tree().get_nodes_in_group("bullets"):
		bullet.queue_free()

	builder.clear()

	var generator := DungeonGenerator.new()
	generator.start_templates = start_templates
	generator.normal_templates = normal_templates
	generator.empty_room_template = empty_room_template
	generator.target_room_count = target_room_count + (current_floor - 1) * rooms_per_floor_increment

	var layout := generator.generate()

	builder.cell_size = cell_size
	builder.build(layout)

	_spawn_player_and_camera(layout[0], preserve_player)  # layout[0] is always the start room by construction

	room_manager.builder = builder
	room_manager.camera = _camera
	room_manager.cell_size = cell_size
	room_manager.setup(layout, layout[0].id)


## preserve_player: reposition the existing player node (keeping HP/buffs)
## instead of recreating it, for floor advances rather than a new run.
func _spawn_player_and_camera(start_room: PlacedRoom, preserve_player: bool = false) -> void:
	var start_center := (Vector2(start_room.occupied_cells[0]) + Vector2(0.5, 0.5)) * cell_size

	if preserve_player and _player != null:
		_player.global_position = start_center
	else:
		if _player:
			# queue_free() is deferred, so pull the old player out of the
			# "player" group now - a same-frame group lookup (room_manager.setup())
			# could otherwise still find it instead of the new one below.
			_player.remove_from_group("player")
			_player.queue_free()

		_player = player_scene.instantiate()
		add_child(_player)
		_player.process_mode = Node.PROCESS_MODE_PAUSABLE
		_player.global_position = start_center
		if _player.has_signal("died"):
			_player.died.connect(_on_player_died)

	# Reuse one Camera2D across restarts - a brand new camera added the same
	# frame as a deferred queue_free() could race it for "current" status.
	if _camera == null:
		_camera = Camera2D.new()
		add_child(_camera)
	_camera.zoom = camera_zoom
	_camera.enabled = true
	_camera.global_position = start_center
	_camera.make_current()
