extends Control
var hits := 0
var label: Label
func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0f0e14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "rigfx arena — Godot build"
	title.add_theme_color_override("font_color", Color("ffb84a"))
	title.add_theme_font_size_override("font_size", 28)
	title.position = Vector2(150, 50)
	add_child(title)
	label = Label.new()
	label.text = "click the rig to train it"
	label.position = Vector2(220, 120)
	label.add_theme_color_override("font_color", Color("e9e6f5"))
	add_child(label)
	var btn := Button.new()
	btn.text = "TRAIN"
	btn.position = Vector2(270, 180)
	btn.custom_minimum_size = Vector2(100, 44)
	btn.pressed.connect(_on_train)
	add_child(btn)
func _on_train() -> void:
	hits += 1
	label.text = "reps: %d  (the rig gets stronger)" % hits
