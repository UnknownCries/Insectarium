extends CanvasLayer

const TOGGLE_KEY := KEY_F3

var _label: Label
var _visible: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128  # above the HUD and every menu overlay

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1, 1, 0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -120.0
	_label.offset_top = 2.0
	_label.offset_right = -2.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == TOGGLE_KEY:
			_visible = not _visible
			_label.visible = _visible


func _process(_delta: float) -> void:
	if not _visible:
		return

	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var bullets := get_tree().get_nodes_in_group("bullets").size()

	_label.text = "FPS %d\nproc %.2f ms\nphys %.2f ms\nenemies %d\nbullets %d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		enemies,
		bullets,
	]
