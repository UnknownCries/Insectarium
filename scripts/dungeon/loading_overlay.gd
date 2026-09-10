class_name LoadingOverlay
extends CanvasLayer

## Full-black "Floor N Loading..." screen shown for a fixed beat during a
## floor transition (see dungeon_root.gd::_rebuild_with_loading_screen).
## Purely cosmetic pacing - the rebuild itself is fast enough to be instant.

@onready var label: Label = $Control/Center/Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func show_for_floor(floor_number: int) -> void:
	label.text = "Floor %d loading..." % floor_number
	show()
