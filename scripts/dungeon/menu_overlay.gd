class_name MenuOverlay
extends CanvasLayer

## Reusable full-screen menu: a dimmed background, a big centered title, and
## two stacked buttons. Used for both the game-over and pause screens -
## configure() sets the text, primary_pressed/secondary_pressed report
## which button was clicked. Runs with PROCESS_MODE_ALWAYS so its buttons
## stay clickable even while get_tree().paused is true.

signal primary_pressed
signal secondary_pressed

@onready var dim: ColorRect = $Control/Dim
@onready var title_label: Label = $Control/Center/VBox/Title
@onready var primary_button: Button = $Control/Center/VBox/PrimaryButton
@onready var secondary_button: Button = $Control/Center/VBox/SecondaryButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	primary_button.pressed.connect(func(): primary_pressed.emit())
	secondary_button.pressed.connect(func(): secondary_pressed.emit())
	hide()

func configure(title: String, primary_text: String, secondary_text: String, dim_color: Color = Color(0, 0, 0, 0.6)) -> void:
	title_label.text = title
	primary_button.text = primary_text
	secondary_button.text = secondary_text
	dim.color = dim_color
