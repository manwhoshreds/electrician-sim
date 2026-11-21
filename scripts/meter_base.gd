class_name MeterBase
extends Interactable
## A house's 200 A meter base, from art/meter_base.py: the can on the wall with
## the socket inside, the cover, the utility's red tag seal on the cover latch,
## and the meter plugged into the jaws. Snip the seal, take the cover off and
## the meter pulls straight out. The origin is on the wall, +Z out of it.
## What you're allowed to do with it is up to the PowerCompany.

const MODEL := "res://assets/meter_base/meter_base.glb"
const DRAW_DISTANCE := 70.0

signal pulled(meter: MeterBase)  # the power company hears about this

var address := ""
var company: Node                # the PowerCompany: for calling in a disconnect
var street := Vector3.ZERO      # where a truck would pull up for this house
var ground := -1.5              # local height of the ground under it
var sealed := true
var cover_on := true
var meter_in := true

var _cover: Node3D
var _seal: Node3D
var _meter: Node3D
var _rest := {}                 # each piece's place on the wall
var _sound: AudioStreamPlayer3D
# The close-up: like the panel, you work it with your hands and tools.
var _open := false
var _player: Node3D
var _tool := "hand"              # or "snips"
var _hover := {}
var _cam: Camera3D
var _ui: CanvasLayer
var _overlay: Control
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _tool_buttons := {}

static var _snip_sound: AudioStreamWAV
static var _clunk_sound: AudioStreamWAV


func _ready() -> void:
	super()
	reach = 1.4
	aim_radius = 0.25
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = DRAW_DISTANCE
	_cover = model.get_node("Cover")
	_seal = model.get_node("Seal")
	_meter = model.get_node("Meter")
	for piece: Node3D in [_cover, _seal, _meter]:
		_rest[piece] = piece.transform
	on_use = open
	_build_closeup()
	_sound = AudioStreamPlayer3D.new()
	_sound.position = Vector3(0, 0, 0.2)
	add_child(_sound)
	_update_prompt()


## How it was left, for the save file.
func to_save() -> Dictionary:
	return {"sealed": sealed, "cover_on": cover_on, "meter_in": meter_in}


## Puts it back how the save file says, with every piece already where it ended up.
func load_save(d: Dictionary) -> void:
	sealed = bool(d.get("sealed", true))
	cover_on = bool(d.get("cover_on", true))
	meter_in = bool(d.get("meter_in", true))
	_seal.transform = _rest[_seal] if sealed else _seal_dropped()
	_cover.transform = _rest[_cover] if cover_on else _cover_aside()
	_meter.transform = _rest[_meter] if meter_in else _meter_down()
	_update_prompt()


# Where each piece ends up when it's off: the tag in the grass under the meter,
# the cover leaned against the wall beside it, the meter face up on the grass.
func _seal_dropped() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0.06, ground + 0.004, 0.3))


func _cover_aside() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0.45, ground + 0.19, 0.12))


func _meter_down() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(-0.4, ground + 0.05, 0.3))


func cut_seal() -> void:
	sealed = false
	_play(_snip(), 1.0)
	_move(_seal, _seal_dropped(), 0.45)
	_update_prompt()


func remove_cover() -> void:
	cover_on = false
	_play(_clunk(), 1.3)
	var out := _rest[_cover] as Transform3D
	out.origin.z += 0.25
	# Off, then leaned against the wall beside the meter.
	_move(_cover, out, 0.25).tween_property(_cover, "transform", _cover_aside(), 0.45)
	_update_prompt()


func refit_cover() -> void:
	cover_on = true
	_play(_clunk(), 1.1)
	_move(_cover, _rest[_cover], 0.4)
	_update_prompt()


func pull_meter() -> void:
	meter_in = false
	_play(_clunk(), 0.8)
	var out := _rest[_meter] as Transform3D
	out.origin.z += 0.2
	# Out of the jaws, then set down face up on the grass.
	_move(_meter, out, 0.35).tween_property(_meter, "transform", _meter_down(), 0.5)
	_update_prompt()


func plug_meter() -> void:
	meter_in = true
	_play(_clunk(), 0.9)
	var out := _rest[_meter] as Transform3D
	out.origin.z += 0.2
	_move(_meter, out, 0.45).tween_property(_meter, "transform", _rest[_meter], 0.2)
	_update_prompt()


## What the utility crew does: everything back where it was, with a fresh seal.
func restore() -> void:
	sealed = true
	cover_on = true
	meter_in = true
	for piece: Node3D in [_cover, _seal, _meter]:
		piece.transform = _rest[piece]
	_update_prompt()


# --- Close-up -------------------------------------------------------------------------

func open(p: Node3D) -> void:
	_player = p
	_open = true
	p.target = self
	p.hud.set_closeup(true, [["LMB", "Use Tool"], ["1/2", "Hand / Snips"], ["P", "Call the power co."], ["Esc", "Step Back"]])
	_cam.make_current()
	_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_open = false
	_player.target = null
	_player.hud.set_closeup(false)
	_player.camera.make_current()
	_ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not _open:
		return
	_hover = _pick_at(get_viewport().get_mouse_position())
	_toast_t -= delta
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_hint.text = _hint_text()
	_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_select("hand")
			KEY_2:
				_select("snips")
			KEY_P:
				_call()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := _pick_at(event.position)
		if not p.is_empty():
			_click(p["kind"])
		get_viewport().set_input_as_handled()


func _select(t: String) -> void:
	_tool = t
	(_tool_buttons[t] as Button).button_pressed = true


func _picks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seal_at: Vector3 = (_rest[_seal] as Transform3D).origin
	var meter_at: Vector3 = (_rest[_meter] as Transform3D).origin
	if _tool == "snips":
		if sealed:
			out.append({"kind": "snip", "pos": seal_at, "label": "Snip the seal"})
		return out
	if sealed:
		out.append({"kind": "sealed", "pos": seal_at + Vector3(0, 0.03, 0), "label": "Utility's tag seal through the latch. Snips (2) to cut it."})
	elif cover_on:
		out.append({"kind": "cover_off", "pos": Vector3(0, -0.145, 0.11), "label": "Pop the latch and lift the cover off"})
	elif meter_in:
		out.append({"kind": "pull", "pos": meter_at + Vector3(0, 0, 0.12), "label": "Pull the meter straight out of its jaws"})
		out.append({"kind": "cover_on", "pos": Vector3(0, -0.16, 0.06), "label": "Put the cover back on"})
	else:
		out.append({"kind": "plug", "pos": meter_at + Vector3(0, 0, 0.05), "label": "Plug the meter back into its jaws"})
	return out


func _click(kind: String) -> void:
	match kind:
		"snip":
			cut_seal()
			_say("Snip. The tag drops into the grass.")
		"sealed":
			_say("It's a crimped wire seal. You'll need the snips.")
		"cover_off":
			remove_cover()
		"cover_on":
			refit_cover()
		"pull":
			pull_meter()
			_say("Out. The whole house is dead now, line side and all.")
			pulled.emit(self)
		"plug":
			plug_meter()
			_say("Back in. Power's on.")


func _call() -> void:
	if company != null:
		_say(company.call_for(self), 5.0)


func _hint_text() -> String:
	var cleared: bool = company != null and company.is_cleared(self)
	if sealed:
		return "Snips (2): cut the seal." + ("" if cleared else "  Call the power company first (P), or it's tampering.")
	if cover_on:
		return "Hand (1): take the cover off."
	if meter_in:
		return "Hand: pull the meter. The line side behind it stays hot." + ("" if cleared else "  Not called in: they WILL notice.")
	return "Meter's out. Hand: plug it back in when you're done."


func _pick_at(mouse: Vector2) -> Dictionary:
	var best := {}
	var best_d := 26.0
	for p: Dictionary in _picks():
		var d := _cam.unproject_position(to_global(p["pos"])).distance_to(mouse)
		if d < best_d:
			best = p
			best_d = d
	return best


func _say(text: String, seconds := 2.5) -> void:
	_toast.text = text
	_toast_t = seconds


func _build_closeup() -> void:
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.02
	_cam.position = Vector3(0.2, 0.06, 0.85)
	add_child(_cam)
	_cam.basis = Basis.looking_at(Vector3(0, -0.02, 0.08) - _cam.position, Vector3.UP)
	_ui = CanvasLayer.new()
	_ui.layer = 5
	_ui.visible = false
	add_child(_ui)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_ui.add_child(_overlay)
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, 0)
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -86.0
	bar.add_theme_constant_override("separation", 6)
	_ui.add_child(bar)
	var group := ButtonGroup.new()
	for t in [["hand", "1  Hand"], ["snips", "2  Snips"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 64)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_select.bind(t[0]))
		bar.add_child(b)
		_tool_buttons[t[0]] = b
	var phone := Button.new()
	phone.text = "P  Call the power company"
	phone.focus_mode = Control.FOCUS_NONE
	phone.custom_minimum_size = Vector2(300, 64)
	phone.add_theme_font_size_override("font_size", 19)
	phone.pressed.connect(_call)
	bar.add_child(phone)
	(_tool_buttons["hand"] as Button).button_pressed = true
	_hint = _ui_label(22, Color(1.0, 0.82, 0.35), Control.PRESET_CENTER_BOTTOM, -150.0)
	_toast = _ui_label(28, Color(1, 1, 1), Control.PRESET_CENTER_TOP, 150.0)


func _ui_label(size: int, c: Color, preset: int, offset: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.position.y += offset
	_ui.add_child(l)
	return l


func _draw_overlay() -> void:
	if _hover.is_empty():
		return
	var at := _cam.unproject_position(to_global(_hover["pos"]))
	_overlay.draw_arc(at, 14.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2), 2.5, true)
	var text: String = _hover["label"]
	Hud.draw_tag(_overlay, at + Vector2(24, 0), text)


func _update_prompt() -> void:
	if sealed:
		prompt = "[E] Electric meter (sealed)"
	elif cover_on:
		prompt = "[E] Meter cover"
	elif meter_in:
		prompt = "[E] Meter"
	else:
		prompt = "[E] Meter socket"


func _move(piece: Node3D, to: Transform3D, seconds: float) -> Tween:
	var t := create_tween()
	t.tween_property(piece, "transform", to, seconds).set_trans(Tween.TRANS_SINE)
	return t


func _play(stream: AudioStreamWAV, pitch: float) -> void:
	_sound.stream = stream
	_sound.pitch_scale = pitch
	_sound.play()


static func _snip() -> AudioStreamWAV:
	if _snip_sound == null:
		_snip_sound = _burst(0.05, 0.9, 0.0)
	return _snip_sound


static func _clunk() -> AudioStreamWAV:
	if _clunk_sound == null:
		_clunk_sound = _burst(0.18, 0.7, 90.0)
	return _clunk_sound


## A short noisy hit, with a low thump under it if thump_hz is set.
static func _burst(seconds: float, level: float, thump_hz: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / rate
		var fade := pow(1.0 - float(i) / n, 3.0)
		var s := rng.randf_range(-1.0, 1.0) * (0.35 if thump_hz > 0.0 else 1.0)
		if thump_hz > 0.0:
			s += sin(TAU * thump_hz * t) * 0.9
		data.encode_s16(i * 2, int(clampf(s * fade * level, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
