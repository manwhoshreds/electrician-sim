class_name CheatConsole
extends CanvasLayer
## For testing: ` (the key under Esc) opens a line to type a cheat into.
##   job recessed      only that kind of call from now on (any file in data/jobs)
##   job any           back to normal dispatch
##   jobs              list the kinds
##   money 2000        set your cash
##   give Romex 2      parts onto the truck (any part id; count's optional)
##   kit recessed      everything the recessed job needs, into your bag
##   help

var main: Node
var service: ServiceCall
var player: Player

var _box: PanelContainer
var _line: LineEdit
var _out: Label
var _open := false


func _ready() -> void:
	layer = 5
	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_top = 170
	_box.offset_left = 360
	_box.offset_right = -360
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.94)
	style.border_color = Color(0.95, 0.75, 0.2)
	style.border_width_left = 4
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_box.add_theme_stylebox_override("panel", style)
	add_child(_box)
	var col := VBoxContainer.new()
	_box.add_child(col)
	_out = Label.new()
	_out.add_theme_font_size_override("font_size", 17)
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.text = "CHEATS (testing). Type help."
	col.add_child(_out)
	_line = LineEdit.new()
	_line.placeholder_text = "job recessed"
	_line.add_theme_font_size_override("font_size", 20)
	_line.text_submitted.connect(_submit)
	col.add_child(_line)
	_box.visible = false


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if player.target != null or player.driving != null:
		return
	_open = true
	_box.visible = true
	player.target = self              # no walking while you type
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_line.clear()
	_line.grab_focus.call_deferred()


func close() -> void:
	_open = false
	_box.visible = false
	_line.release_focus()
	if player.target == self:
		player.target = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _submit(text: String) -> void:
	_out.text = run(text)
	_line.clear()


## Runs one cheat. What it did, in words.
func run(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.is_empty():
		return "Type help."
	var arg := words[1] if words.size() > 1 else ""
	match words[0].to_lower():
		"help":
			return "job <kind> | job any | jobs | money <n> | give <part> [n] | kit recessed   (` or Esc closes)"
		"jobs":
			return ", ".join(JobType.dispatchable().map(func(d: JobType) -> String: return d.kind))
		"job":
			return main.only_calls(arg if arg != "" else "any")
		"money":
			if not arg.is_valid_int():
				return "money <amount>"
			service.wallet.money = int(arg)
			service.hud.set_money(service.wallet.money)
			return "You've got $%d." % service.wallet.money
		"give":
			if not PartSpec.has(arg):
				return "No part '%s'. Parts: %s" % [arg, ", ".join(PartSpec.ORDER)]
			var n := int(words[2]) if words.size() > 2 and words[2].is_valid_int() else 1
			for i in n:
				service.inventory.add(arg)
			return "%d x %s on the truck." % [n, PartSpec.of(arg).name]
		"kit":
			if arg != "recessed":
				return "kit recessed"
			var on_truck := 0
			for part in ["Blank", "Romex", "GuardStrip", "GuardStrip"]:
				if not service.inventory.carry(part):
					service.inventory.add(part)
					on_truck += 1
			return "Blank cover, a coil of 14/2 and two 2x4 guard strips in your bag%s. The customer has the wafers." % (
					"" if on_truck == 0 else " (%d on the truck: the bag's full)" % on_truck)
	return "Don't know '%s'. Type help." % words[0]
