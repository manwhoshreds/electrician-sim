class_name DialogueBox
extends CanvasLayer
## Conversation box along the bottom of the screen. Each option is
## ["what you say", Callable]. Click one, or press its number key.

var _name: Label
var _text: Label
var _options: VBoxContainer
var _actions: Array[Callable] = []


func _ready() -> void:
	layer = 6
	visible = false
	var box := PanelContainer.new()
	box.anchor_left = 0.2
	box.anchor_right = 0.8
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_bottom = -30.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.93)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	box.add_theme_stylebox_override("panel", style)
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	box.add_child(col)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2))
	col.add_child(_name)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 26)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	col.add_child(_options)


func say(speaker: String, text: String, options: Array) -> void:
	_name.text = speaker
	_text.text = text
	_actions.clear()
	for c in _options.get_children():
		_options.remove_child(c)
		c.queue_free()
	for i in options.size():
		var opt: Array = options[i]
		var button := Button.new()
		button.text = "%d.  %s" % [i + 1, opt[0]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(_choose.bind(i))
		_options.add_child(button)
		_actions.append(opt[1])
	visible = true


func close() -> void:
	visible = false


## Deferred because the action usually rebuilds the buttons being pressed.
func _choose(i: int) -> void:
	_actions[i].call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var i: int = (event as InputEventKey).physical_keycode - KEY_1
	if i >= 0 and i < _actions.size():
		_choose(i)
		get_viewport().set_input_as_handled()
