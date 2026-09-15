extends CanvasLayer

## Optional on-screen performance readout, for capturing the FPS figures the
## report needs without reading them off the editor's Debugger panel.
##
## Not part of the game. To use it, add this script as an autoload
## (Project > Project Settings > Globals > Add, path res://benchmark/fps_overlay.gd),
## run the game, and press F3 to toggle the readout. Remove the autoload
## again before exporting a build.
##
## The game renders at a 320x180 viewport, so the label is deliberately tiny
## and pinned to the top-right corner, clear of the HUD in the top-left.

const TOGGLE_KEY := KEY_F3

var _label: Label
var _visible: bool = true


func _ready() -> void:
	# Must keep running while the tree is paused, otherwise the readout
	# freezes on the pause screen exactly when it is easiest to screenshot.
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

	# get_nodes_in_group() every frame is fine here - this overlay is a
	# measurement tool, not shipped code, and the counts are what the
	# report's "FPS vs. number of pathfinding enemies" table needs.
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var bullets := get_tree().get_nodes_in_group("bullets").size()

	_label.text = "FPS %d\nproc %.2f ms\nphys %.2f ms\nenemies %d\nbullets %d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		enemies,
		bullets,
	]
